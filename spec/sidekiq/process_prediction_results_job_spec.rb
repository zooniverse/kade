# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProcessPredictionResultsJob, type: :job do
  describe 'perform' do
    let(:prediction_job) do
      PredictionJob.create(
        service_job_url: 'https://bajor-staging.zooniverse.org/prediction/job/64bf4fab-ed6d-4f9a-b8ae-004086e3676f',
        manifest_url: 'https://manifest-host/manifest.csv',
        results_url: 'https://fake.com/results.json',
        state: :completed,
        subject_set_id: 1,
        probability_threshold: 0.5,
        randomisation_factor: 0.5
      )
    end
    let(:prediction_results_process_service_double) { instance_double(PredictionResults::Process) }
    let(:job) { described_class.new }

    before do
      allow(prediction_results_process_service_double).to receive(:run)
      allow(PredictionResults::Process).to receive(:new).and_return(prediction_results_process_service_double)
    end

    it 'calls the PredictionResults::Process service', :aggregate_failures do
      job.perform(prediction_job.id)
      expect(PredictionResults::Process).to have_received(:new).with(
        results_url: prediction_job.results_url,
        subject_set_id: prediction_job.subject_set_id,
        probability_threshold: prediction_job.probability_threshold,
        randomisation_factor: prediction_job.randomisation_factor
      )
      expect(prediction_results_process_service_double).to have_received(:run)
    end

    it 'dispatches catalogue snapshots to the candidate result processor' do
      prediction_job.update!(catalogue_snapshot: { 'project_id' => 1 })
      processor = instance_double(CandidatePool::ProcessResults, run: nil)
      allow(CandidatePool::ProcessResults).to receive(:new).with(prediction_job).and_return(processor)
      job.perform(prediction_job.id)
      expect(processor).to have_received(:run)
      expect(PredictionResults::Process).not_to have_received(:new)
    end
  end
end
