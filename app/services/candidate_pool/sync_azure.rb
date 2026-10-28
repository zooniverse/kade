# frozen_string_literal: true

module CandidatePool
  class SyncAzure
    IMAGE_TYPES = {
      '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg', '.png' => 'image/png',
      '.gif' => 'image/gif', '.tif' => 'image/tiff', '.tiff' => 'image/tiff'
    }.freeze

    def initialize(context, blob_client: nil)
      @context = context
      @client = blob_client
    end

    def run
      raise ArgumentError, 'context must use azure_catalogue' unless @context.azure_catalogue?
      @context.validate!
      container = Zoobot::Storage.container_name
      @client ||= Azure::Storage::Blob::BlobService.create(
        storage_account_name: ENV.fetch('AZURE_STORAGE_ACCOUNT_NAME'),
        storage_access_key: ENV.fetch('AZURE_STORAGE_ACCESS_KEY')
      )

      rows = []
      marker = nil
      loop do
        page = @client.list_blobs(container, prefix: "#{Zoobot::Storage::CONTAINER_IMAGE_PATH_PREFIX}/", marker: marker)
        page.each do |blob|
          mime_type = IMAGE_TYPES[File.extname(blob.name).downcase]
          next unless mime_type

          rows << {
            'external_id' => "#{container}/#{blob.name}",
            'metadata' => { '!filename' => File.basename(blob.name) },
            'locations' => [{ mime_type => @client.generate_uri("#{container}/#{blob.name}", {}, encode: true).to_s }]
          }
        end
        marker = page.continuation_token
        break if marker.blank?
      end

      rows
    end
  end
end
