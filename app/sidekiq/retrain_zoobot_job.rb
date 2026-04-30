# frozen_string_literal: true
require 'bajor/client'
require 'honeybadger/ruby'

class RetrainZoobotJob
  class Failure < StandardError; end

  include Sidekiq::Job

  RECENT_TRAINING_EXPORT_WINDOW = ENV.fetch('RECENT_TRAINING_EXPORT_WINDOW', 12).to_i
  TRAINING_JOB_MONITOR = ENV.fetch('TRAINING_JOB_MONITOR', 10).to_i

  def perform(context_id)
    begin
      training_context = Context.find(context_id)

      # see if we have a recent re-usable data export instead of making one each time
      # the data should be similar and the window period is configurable
      training_data_export = find_recent_training_data_export(training_context.workflow_id)

      # if we haven't found a recent training data export then create one
      unless training_data_export
        training_data_export = TrainingDataExport.create!(
          storage_path: TrainingDataExport.storage_path(training_context.workflow_id),
          workflow_id: training_context.workflow_id
        )

        # run the export service code to create the training data export catalogue on blob storage system
        Export::TrainingData.new(training_data_export).run
      end

      # this is where we could intercept the training job submission
      # to avoid a training run if there isn't enough data for a viable model
      # one idea would be to check the number of rows in the training data export attached file
      # or even better we store the number of exported rows in the training data export model
      # https://github.com/zooniverse/kade/issues/62

      # create a new training job record to track the batch training job
      training_job = create_training_job(training_data_export.storage_path, training_context.workflow_id)
      # submit the export training job to the batch training service
      # this updates the training job state
      training_job = Batch::Training::CreateJob.new(training_job).run

      # raise a failure here to rely on sidekiq to retry the job
      # and notify us that there are issues with job submission
      # Note: if this gets noisy we can look at silencing the error reporting
      raise Failure, "failure when submiting the training job with id: #{training_job.id}" if training_job.failed?

      # kick off a job monitor here that updates the training job resource with the job tasks results
      # this background job will reschedule itself until the training job is completed
      # and handle the completion / failure events for the training job
      TrainingJobMonitorJob.perform_in(TRAINING_JOB_MONITOR.minutes, training_job.id, training_context.id)

      training_job
    rescue StandardError => e
      Honeybadger.notify(e)
      raise
    end
  end

  def find_recent_training_data_export(workflow_id)
    # this query is supported by a compond unique index on
    # the [id workflow_id state] columns that results in a
    # backwards Index Scan to find the most recent finished record we have for this workflow
    recent_training_data_export = TrainingDataExport.where(workflow_id: workflow_id, state: :finished).order(id: :desc).first

    # return nil if the training data export is not recently finished with fresh data
    # this helps avoid running possible expensive data export operations
    # on job failure / re-runs with the recent window period etc
    return nil unless training_data_export_is_recent?(recent_training_data_export)

    recent_training_data_export
  end

  private

  def training_data_export_is_recent?(training_data_export)
    return false unless training_data_export

    training_data_export.created_at >= RECENT_TRAINING_EXPORT_WINDOW.hours.ago
  end

  def create_training_job(blob_storage_manifest_path, workflow_id)
    TrainingJob.create!(
      manifest_url: "#{Bajor::Client::BLOB_STORE_HOST_CONTAINER_URL}#{blob_storage_manifest_path}",
      workflow_id: workflow_id,
      state: :pending
    )
  end
end
