# frozen_string_literal: true

require 'honeybadger/ruby'

class PredictionManifestExportJob
  include Sidekiq::Job

  def perform(context_id)
    begin
      context = Context.find(context_id)
    rescue StandardError => e
      Honeybadger.notify(e, context: { current_step: 'find_context' })
      raise
    end

    # NOTE: if we have a failure anywhere after this point sadly we pay the cost to recreate the manifest
    # ideally we'd add a PredictionExport resource model to track the creation
    # and some smarts here to re-use an existing, recent manifest (perhaps 12 hours?)
    # to avoid reprocessing the same data if we have a job failure (creation / submissione etc)
    export_manifest_service = if context.azure_catalogue?
                                CandidatePool::ExportManifest.new(context)
                              else
                                Batch::Prediction::ExportManifest.new(context.pool_subject_set_id)
                              end
    export_manifest_service.run

    # create a prediction job resource
    begin
      attributes = prediction_job_params(
        context.active_subject_set_id,
        export_manifest_service.manifest_url
      )
      if context.azure_catalogue?
        snapshot = export_manifest_service.snapshot
        attributes.merge!(
          context_id: context.id, catalogue_snapshot: snapshot,
          probability_threshold: snapshot.fetch('selection').fetch('probability_threshold'),
          randomisation_factor: snapshot.fetch('selection').fetch('randomisation_factor')
        )
      end
      prediction_job = PredictionJob.create!(attributes)
    rescue StandardError => e
      Honeybadger.notify(
        e,
        context: {
          current_step: 'create_prediction_job'
        }
      )
      raise
    end

    # submit the prediction job for processing
    begin
      prediction_job_submission_job_id = PredictionJobSubmissionJob.perform_async(prediction_job.id)
      Honeybadger.notify(
        StandardError.new('PredictionManifestExportJob did not enqueue PredictionJobSubmissionJob'),
        context: {
          current_step: 'enqueue_prediction_job_submission'
        }
      ) unless prediction_job_submission_job_id
    rescue StandardError => e
      Honeybadger.notify(
        e,
        context: {
          current_step: 'enqueue_prediction_job_submission'
        }
      )
      raise
    end
  end

  private

  # NOTE: These are the same as in the predictions_controller
  # perhaps these can be extracted to a common service object that allows
  # for args that overrdie the env default values
  # DRY vs KISS and don't abstract too early
  def prediction_job_params(subject_set_id, manifest_url)
    {
      state: :pending,
      manifest_url: manifest_url,
      subject_set_id: subject_set_id,
      # NOTE: the below defaults could also move to the context model as required
      # threshold on subjects 80% predicted not likely to be smooth
      probability_threshold: ENV.fetch('PREDICTION_JOB_PROBABILITY_THRESHOLD_DEFAULT', '0.8').to_f,
      # attempt to add 10% of the 'smooth' prediction subjects for some randomisation of the data (avoid overfitting the model etc)
      randomisation_factor: ENV.fetch('PREDICTION_JOB_RANDOMISATION_FACTOR_DEFAULT', '0.2').to_f
    }
  end
end
