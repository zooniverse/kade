# frozen_string_literal: true

require 'bajor/client'

module Batch
  module Training
    class CreateJob
      attr_accessor :training_job, :bajor_client

      def initialize(training_job, bajor_client = Bajor::Client.new)
        @training_job = training_job
        @bajor_client = bajor_client
      end

      def run
        begin
          bajor_job_url = bajor_client.create_training_job(training_job.manifest_path, training_options)
          training_job.update(state: :submitted, service_job_url: bajor_job_url, message: '')
        rescue Bajor::Client::Error => e
          # mark the jobs as failed and record the client error message
          training_job.update(state: :failed, message: e.message)
        end
        # return the training job as a result object
        training_job
      end

      private
      def training_options
        context = Context.find_by(workflow_id: training_job.workflow_id)
        return {} unless context

        fixed_crop = if context.metadata.is_a?(Hash) && context.metadata['fixed_crop'].is_a?(Hash)
          context.metadata['fixed_crop']
        end

        {
          workflow_name: context.extractor_name,
          fixed_crop: fixed_crop,
        }.compact
      end
    end
  end
end
