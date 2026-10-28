# frozen_string_literal: true

require 'bajor/client'
require 'json'

module CandidatePool
  class ExportManifest
    attr_reader :manifest_url, :snapshot

    def initialize(context)
      @context = context
    end

    def run
      raise ArgumentError, 'context must use azure_catalogue' unless @context.azure_catalogue?

      candidates = SyncAzure.new(@context).run
      raise ArgumentError, 'candidate catalogue is empty' if candidates.empty?

      @snapshot = {
        'project_id' => @context.project_id,
        'selection' => @context.candidate_selection
      }
      manifest_rows = candidates.map do |candidate|
        mime_type, url = candidate.fetch('locations').sole.first
        [url, JSON.generate(
          project_id: @context.project_id,
          subject_id: candidate.fetch('external_id'),
          mime_type: mime_type,
          metadata: candidate.fetch('metadata')
        )]
      end

      Tempfile.create(['candidate-manifest', '.json']) do |file|
        file.write(JSON.generate(manifest_rows))
        file.rewind
        key = "/catalogues/#{Rails.env}/candidates-#{@context.id}-#{SecureRandom.uuid}.json"
        blob = ActiveStorage::Blob.create_and_upload!(
          key: key, io: file, filename: File.basename(key),
          service_name: "#{Rails.env}-predictions"
        )
        @manifest_url = "#{Bajor::Client::BLOB_STORE_HOST_CONTAINER_URL}/predictions#{blob.key}"
      end
      self
    end
  end
end
