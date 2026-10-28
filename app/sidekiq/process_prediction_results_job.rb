# frozen_string_literal: true

class ProcessPredictionResultsJob
  include Sidekiq::Job

  def perform(prediction_job_id)
    prediction_job = PredictionJob.find(prediction_job_id)
    if prediction_job.catalogue_snapshot
      CandidatePool::ProcessResults.new(prediction_job).run
      return
    end
    # use the prediction job values but allow them to be injected independently for flexibility
    prediction_results_process_service = PredictionResults::Process.new(
      results_url: prediction_job.results_url,
      subject_set_id: prediction_job.subject_set_id,
      probability_threshold: prediction_job.probability_threshold,
      randomisation_factor: prediction_job.randomisation_factor
    )
    prediction_results_process_service.run
  end
end
