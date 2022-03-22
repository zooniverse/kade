# frozen_string_literal: true

module Storage
  class TrainingDataSync
    COPY_OPERATION_SUCCESS_CODE = 'success'

    attr_accessor :src_image_url

    def initialize(src_image_url)
      @src_image_url = src_image_url
    end

    def run
      return if copy_operation_status == COPY_OPERATION_SUCCESS_CODE

      _copy_id, _copy_status = blob_service_client.copy_blob_from_uri(
        Rails.env,
        blob_destination_path,
        src_image_url
      )
    end

    def copy_operation_status
      blob_service_client.get_blob_properties(Rails.env, blob_destination_path).properties[:copy_status]
    end

    private

    def blob_service_client
      @blob_service_client ||= Azure::Storage::Blob::BlobService.create(
        storage_account_name: ENV['AZURE_STORAGE_ACCOUNT_NAME'],
        storage_access_key: ENV['AZURE_STORAGE_ACCESS_KEY']
      )
    end

    def blob_destination_path
      @blob_destination_path ||= Zoobot.training_image_path(src_image_url)
    end
  end
end
