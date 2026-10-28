# frozen_string_literal: true

require 'remote_file/reader'
require 'panoptes/api'

module CandidatePool
  class ProcessResults
    def initialize(prediction_job, panoptes_client: nil)
      @job = prediction_job
      @client = panoptes_client
    end

    def run
      with_context_lock do
        @job.reload
        next if @job.applied_at

        newer = @job.context.prediction_jobs.where('id > ?', @job.id)
                    .where.not(selection: nil).order(id: :desc).first
        if newer
          @job.update!(message: "Superseded by prediction job #{newer.id}")
          next
        end

        # Saving selection also prevents older runs from undoing a partially applied run.
        @job.update!(selection: select_subjects) if @job.selection.nil?
        Sync { apply_selection }
        @job.update!(applied_at: Time.current)
      end
    ensure
      Faraday.default_connection.close if @client
    end

    private

    def with_context_lock
      # A session lock serializes remote work without rolling back saved mappings on failure.
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        key = Integer(@job.context_id)
        connection.execute("SELECT pg_advisory_lock(#{key})")
        begin
          yield
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{key})")
        end
      end
    end

    def candidates
      @candidates ||= begin
        rows = nil
        RemoteFile::Reader.stream_to_tempfile(@job.manifest_url) do |file|
          rows = JSON.parse(file.read)
        end
        unless rows.is_a?(Array) && rows.any?
          raise ArgumentError, 'prediction manifest must be a nonempty array'
        end
        catalogue = {}
        rows.each do |url, json|
          metadata = JSON.parse(json)
          external_id = metadata.fetch('subject_id')
          unless external_id.is_a?(String) && external_id.present? && !catalogue.key?(external_id) &&
                 metadata.fetch('project_id').to_s == @job.catalogue_snapshot.fetch('project_id').to_s
            raise ArgumentError, 'manifest needs unique subject IDs and the prediction project'
          end
          catalogue[external_id] = {
            'metadata' => metadata.fetch('metadata'),
            'locations' => [{ metadata.fetch('mime_type') => url }]
          }
        end
        catalogue
      end
    end

    def select_subjects
      data = nil
      RemoteFile::Reader.stream_to_tempfile(@job.results_url) do |file|
        data = JSON.parse(file.read).fetch('data')
      end
      expected_keys = candidates.keys
      unless data.is_a?(Hash) && data.keys.sort == expected_keys.sort
        raise ArgumentError, 'prediction results must contain exactly one result for every candidate subject'
      end

      scores = candidates.keys.to_h do |external_id|
        [external_id, prediction_score(data.fetch(external_id))]
      end
      over, under = scores.keys.partition { |id| scores.fetch(id) >= @job.probability_threshold }
      random = under.sample((over.size * @job.randomisation_factor).floor)
      { 'scores' => scores, 'selected' => over + random, 'random_sample' => random }
    end

    def prediction_score(result)
      score = result.fetch('0').fetch(0)
      unless score.is_a?(Numeric) && score.finite? && score.between?(0, 1)
        raise ArgumentError, 'prediction score must be a finite number between 0 and 1'
      end
      score
    rescue IndexError, NoMethodError, TypeError
      raise ArgumentError, 'prediction must contain sample 0 with a score as its first value'
    end

    def apply_selection
      selected = @job.selection.fetch('selected').map do |external_id|
        attributes = candidates.fetch(external_id)
        candidate = @job.context.candidate_subjects.find_or_initialize_by(external_id: external_id)
        if candidate.persisted? && candidate.attributes.slice(*attributes.keys) != attributes
          raise ArgumentError, "candidate #{external_id} already exists with different media or metadata"
        end
        candidate.assign_attributes(attributes)
        candidate.validate!
        candidate
      end

      @client ||= Panoptes::Api.client
      project_id = @job.catalogue_snapshot.fetch('project_id')
      set = @client.subject_set(@job.subject_set_id)
      unless set.dig('links', 'project').to_s == project_id.to_s
        raise ArgumentError, 'active subject set does not belong to the catalogue project'
      end

      current_ids = @client.subjects(subject_set_id: @job.subject_set_id).map { |subject| subject.fetch('id').to_s }
      desired_ids = selected.map do |candidate|
        register(candidate, project_id)
        candidate.zooniverse_subject_id.to_s
      end
      owned_ids = @job.context.candidate_subjects.where.not(zooniverse_subject_id: nil)
                      .pluck(:zooniverse_subject_id).map(&:to_s)

      (desired_ids - current_ids).each_slice(10) do |ids|
        @client.add_subjects_to_subject_set(@job.subject_set_id, ids)
      end
      ((owned_ids & current_ids) - desired_ids).each_slice(10) do |ids|
        @client.panoptes.delete("/subject_sets/#{@job.subject_set_id}/links/subjects/#{ids.join(',')}")
      end
    end

    def register(candidate, project_id)
      candidate.save! if candidate.new_record?
      now = Time.current
      claimed = CandidateSubject.where(id: candidate.id, zooniverse_subject_id: nil, registration_started_at: nil)
                                .update_all(registration_started_at: now, updated_at: now)
      unless claimed == 1
        candidate.reload
        return if candidate.zooniverse_subject_id

        raise ArgumentError, "candidate #{candidate.id} has an unresolved registration; reconcile its Panoptes ID before retrying"
      end
      # Panoptes references the existing image URL; no media upload occurs.
      response = @client.panoptes.post('/subjects', subjects: {
        external_id: "kade-candidate-#{candidate.id}",
        links: { project: project_id },
        metadata: candidate.metadata.merge('#kade_candidate_id' => candidate.id.to_s),
        locations: candidate.locations
      })
      candidate.update!(zooniverse_subject_id: response.fetch('subjects').first.fetch('id'))
    end
  end
end
