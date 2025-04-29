# frozen_string_literal: true

module Import
  class Reduction
    class InvalidPayload < StandardError; end

    attr_accessor :payload, :label_extractor

    def initialize(payload, label_extractor)
      @payload = payload
      # label extractor injected at run time for the specific project we import data for
      @label_extractor = label_extractor
    end

    def run
      validate_payload

      # compose the Import::Subject service to find or create the subject
      subject = Import::Subject.new(zooniverse_subject_id, context).run

      # upsert to avoid timing collisions from a sender system
      # NOTE: the last sent payload wins but this should not be a problem as any
      # classifications should update the sender system
      # and it should then send again with the latest state
      upsert_results = ::Reduction.upsert_all(
        [{
          raw_payload: payload,
          subject_id: subject.id,
          zooniverse_subject_id: zooniverse_subject_id,
          workflow_id: workflow_id,
          labels: labels,
          unique_id: unique_id,
          task_key: task_key
        }],
        unique_by: %i[workflow_id subject_id task_key],
        update_only: %i[labels raw_payload]
      )
      upserted_reduction_id = upsert_results.to_a.first['id']
      ::Reduction.find(upserted_reduction_id)
    end

    private

    def validate_payload
      return if workflow_id && zooniverse_subject_id && task_key

      raise InvalidPayload, 'missing workflow, subject_id or task_key'
    end

    def context
      Context.find_by(workflow_id: workflow_id)
    end

    def zooniverse_subject_id
      payload.dig('subject', 'id')
    end

    def workflow_id
      return unless for_workflow_reducible

      payload.dig('reducible', 'id')
    end

    def for_workflow_reducible
      payload.dig('reducible', 'type')&.casecmp?('workflow')
    end

    def unique_id
      subject_metadata = payload.dig('subject', 'metadata')
      return unless subject_metadata

      # this is the standard gz metadata for all future uploads
      unique_id = subject_metadata['!filename']
      return unique_id if unique_id

      # this catches various common (non-standard and to be avoided in future) variations
      unique_id = subject_metadata['!Filename'] || subject_metadata['#filename'] || subject_metadata['#Filename'] || subject_metadata['filename'] || subject_metadata['Filename']
      return unique_id if unique_id

      # old cosmic dawn metadata - may be marked as hidden (!id) or private (#id) metadata
      unique_id = subject_metadata['id'] || subject_metadata['!id'] || subject_metadata['#id']
      return unique_id if unique_id

      # old decals metadata
      unique_id = subject_metadata['#name']
      return unique_id if unique_id

      # generic metadata
      unique_id = subject_metadata['id_str'] || subject_metadata['!id_str'] || subject_metadata['#id_str'] || subject_metadata['#id_field']
      return unique_id if unique_id

      # staging has older data with different subject metadata - fallback to handling this special env case
      subject_metadata['!SDSS_ID'] if Rails.env.staging? || Rails.env.test?
    end

    # use a custom label extractor (injected at run time)
    # for the different workflow data reduction payloads
    # to convert the reduced volunteer data (stats reducer)
    # key format lables to human readable string labels
    def labels
      return unless payload['data']

      label_extractor.extract(payload['data'])
    end

    def task_key
      payload['task_key']
    end
  end
end
