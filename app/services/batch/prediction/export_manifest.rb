# frozen_string_literal: true

require 'panoptes/api'
require 'json'

module Batch
  module Prediction
    class ExportManifest
      MANIFEST_SUBJECT_SET_BATCH_SIZE = ENV.fetch('MANIFEST_SUBJECT_SET_BATCH_SIZE', '10').to_i

      MAX_RETRIES = 3
      BASE_BACKOFF_SECONDS = 0.5
      attr_accessor :subject_set_id, :panoptes_client_pool, :manifest_data, :subject_set, :project_id, :temp_file, :subject_set_subject_ids
      attr_reader :manifest_url

      def initialize(subject_set_id, panoptes_client_pool = nil)
        @subject_set_id = subject_set_id
        @panoptes_client_pool = panoptes_client_pool || ConnectionPool.new(size: MANIFEST_SUBJECT_SET_BATCH_SIZE, timeout: 5) { Panoptes::Api.client }
        @manifest_data = []
        @subject_set_subject_ids = []
        @temp_file = Tempfile.new("prediction_manifest_subject_set#{subject_set_id}.csv")
      end

      def run
        panoptes_client_pool.with do |panoptes_client|
          @subject_set = panoptes_client.subject_set(subject_set_id)
          @project_id = subject_set.dig('links', 'project')
          # collection of the subject set subject ids
          fetch_subject_set_subject_ids(panoptes_client)
          # enumerate the subjects and create the manifest data
          create_manifest_data(panoptes_client)
        end

        # write the manifest data to a temp file
        write_manifest_data_to_temp_file

        # upload the manifest to blob storage
        blob = upload_manifest_data_to_blob_storage
        # store the blob url for the uploaded prediction manifest
        # these are public URLs, long term we might want to turn these
        # into signed urls via blob.url etc.
        @manifest_url = "#{Bajor::Client::BLOB_STORE_HOST_CONTAINER_URL}/predictions#{blob.key}"
      ensure
        # cleanup the temp file
        temp_file.close
        temp_file.unlink
      end

      def fetch_subject_set_subject_ids(panoptes_client, slices = MANIFEST_SUBJECT_SET_BATCH_SIZE)
        return if subject_set_id.nil?

        query = { subject_set_id: subject_set_id }
        # this is a hack to get around the fact that the panoptes client
        # as it doesn't support the `set_member_subjects` types
        # we use the SetMemberSubject Resource allows us to enumerate all the subejct ids in the set
        # which we can use to async fetch all the subject resources vs paging through the subject response objects
        # filtering on the subject_set_id
        # note this approach is what the Python Client does but in serial and it's slow
        # https://github.com/zooniverse/panoptes-python-client/blob/4b49b3c789462637fa6cb4677cbe05147dbae9d5/panoptes_client/subject_set.py#L83-L84
        first_page = with_api_retry do
          panoptes_client.panoptes.get('/set_member_subjects', query)
        end
        return unless first_page
        first_page['set_member_subjects'].each do |set_member_subject|
          subject_set_subject_ids << set_member_subject['links']['subject']
        end

        page_count = first_page.dig('meta', 'set_member_subjects', 'page_count')
        return if page_count == 1

        # find the remaining pages of SetMemeberSubjects data asynchronously
        (2..page_count).each_slice(slices) do |page_nums|
          Async do
            results = page_nums.map do |page_num|
              page_query = { subject_set_id: subject_set_id, page: page_num }
              Async do
                resp = with_api_retry do
                  panoptes_client.panoptes.get('/set_member_subjects', page_query)
                end
                next unless resp
                resp
              end
            end.map(&:wait)
            # process the async results into the subject_set_subject_ids
            results.compact.each do |page|
              page['set_member_subjects'].each do |set_member_subject|
                subject_set_subject_ids << set_member_subject['links']['subject']
              end
            end
          ensure
            Faraday.default_connection.close
          end
        end
      end

      def create_manifest_data(panoptes_client, slices = MANIFEST_SUBJECT_SET_BATCH_SIZE)
        subject_set_subject_ids.each_slice(slices) do |batch_of_subject_ids|
          # fetch the subjects asynchronously, https://github.com/socketry/async-http-faraday
          Async do
            subject_responses = batch_of_subject_ids.map do |subject_id|
              Async do
                resp = with_api_retry do
                  panoptes_client.subject(subject_id)
                end
                next unless resp
                resp
              end
            end.map(&:wait)
            subject_responses.compact.each do |subject|
              # Create a data row for the first frame in the Subject
              location = subject['locations'].first
              frame_id = 0
              manifest_data << [
                location.values[0], # image_url
                # The subject's JSON information is stored as a string,
                # Yes, really - this is the format that hamlet sets up.
                JSON.dump(
                  {
                    project_id: project_id,
                    subject_set_id: subject_set_id.to_s,
                    subject_id: subject['id'],
                    frame_id: frame_id.to_s
                  }
                )
              ]
            end
          ensure
            Faraday.default_connection.close
          end
        end
      end

      def write_manifest_data_to_temp_file
        temp_file.write(manifest_data.to_json)
        # rewind the file so it can be read when uploading to storage
        temp_file.rewind
      end

      def upload_manifest_data_to_blob_storage
        # configure the blob storage data and paths
        catalogue_prefix = ENV.fetch('PREDICTIONS_CATALOGUE_PREFIX', "catalogues/#{Rails.env}")
        storage_key = "/#{catalogue_prefix}/subject-set-#{subject_set_id}-#{Time.now.iso8601}.json"
        storage_filename = File.basename(storage_key)
        service_name = "#{Rails.env}-predictions" # see config/storage.yml

        # upload the prediction manifest to blob storage directly
        ActiveStorage::Blob.create_and_upload!(
          key: storage_key,
          io: temp_file,
          filename: storage_filename,
          service_name: service_name
        )
      end


      private
      def with_api_retry(max_retries = MAX_RETRIES)
        attempts = 0

        begin
          yield
        rescue StandardError => e
          attempts += 1
          if attempts < max_retries
            backoff = BASE_BACKOFF_SECONDS * attempts
            Rails.logger.warn(
              "[ExportManifest] Attempt #{attempts}/#{max_retries} raised #{e.class.name}: #{e.message}. " \
              "Retrying in #{backoff}s..."
            )
            sleep(backoff)
            retry
          else
            Rails.logger.warn(
              "[ExportManifest] All #{max_retries} attempts failed: #{e.class.name} – #{e.message}. Skipping."
            )
            return nil
          end
        ensure
          Faraday.default_connection.close
        end
      end
    end
  end
end
