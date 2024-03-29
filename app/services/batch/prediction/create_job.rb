# frozen_string_literal: true

require 'bajor/client'

module Batch
  module Prediction
    class CreateJob
      attr_accessor :prediction_job, :bajor_client

      def initialize(prediction_job, bajor_client = Bajor::Client.new)
        @prediction_job = prediction_job
        @bajor_client = bajor_client
      end

      def run
        begin
          bajor_job_url = bajor_client.create_prediction_job(prediction_job.manifest_url)
          prediction_job.update(state: :submitted, service_job_url: bajor_job_url, message: '')
        rescue Bajor::Client::Error => e
          # mark the jobs as failed and record the client error message
          prediction_job.update(state: :failed, message: e.message)
        end
        # return the prediction job as a result object
        prediction_job
      end
    end
  end
end
