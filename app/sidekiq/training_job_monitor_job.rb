# frozen_string_literal: true

require 'honeybadger/ruby'

class TrainingJobMonitorJob
  class TrainingFailure < StandardError; end
  include Sidekiq::Job

  MONITOR_JOB_RESCHEDULE_DELAY = ENV.fetch('MONITOR_JOB_RESCHEDULE_DELAY', 1).to_i

  def perform(training_job_id, context_id)
    training_job = TrainingJob.find(training_job_id)
    context = Context.find(context_id)

    # short circuit if we run this on a job that's already done
    return if training_job.completed?

    training_job = Batch::Training::MonitorJob.new(training_job).run

    if training_job.failed?
      # notify HB about these errors - longer term remove if noisy
      Honeybadger.notify(
        TrainingFailure.new("Training Job failed, id: #{training_job.id}, message: #{training_job.message}")
      )
      return # avoid rescheduling the job if it's failed or completed
    end

    if training_job.completed?
      # As the training job is finished - we want to run the prediction system using the newly trained model
      # so we call the prediction manifest export job to create a manifest and submit it for batch processing
      #
      # Ensure the prediction system runs over the correct subject sets
      # this information is encoded into the context resource for the workflow, i.e. the
      # pool subject set is the source data for prediciton
      # active subject set is the target for results
      begin
        prediction_manifest_export_job_id = PredictionManifestExportJob.perform_async(context.id)
        Honeybadger.notify(
          StandardError.new('TrainingJobMonitorJob did not enqueue PredictionManifestExportJob'),
          context: {
            current_step: 'enqueue_prediction_manifest_export_job'
          }
        ) unless prediction_manifest_export_job_id
      rescue StandardError => e
        Honeybadger.notify(e, context: { current_step: 'enqueue_prediction_manifest_export_job' })
        raise
      end
    else
      # reschedule this job to run again in 1 minute
      TrainingJobMonitorJob.perform_in(MONITOR_JOB_RESCHEDULE_DELAY.minute, training_job.id, context.id)
    end
  end
end
