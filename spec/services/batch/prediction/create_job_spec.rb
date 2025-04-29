# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Batch::Prediction::CreateJob do
  describe '#run' do
    fixtures :contexts

    let(:manifest_url) { 'https://manifest-host.zooniverse.org/manifest.csv' }
    let(:context){ contexts(:galaxy_zoo_cosmic_active_learning_project) }
    let(:prediction_job) do
      PredictionJob.new(
        manifest_url: manifest_url,
        state: :pending,
        subject_set_id: context.active_subject_set_id,
        probability_threshold: 0.5,
        randomisation_factor: 0.5
      )
    end
    let(:bajor_client_double) { instance_double(Bajor::Client) }
    let(:prediction_create_job) { described_class.new(prediction_job, bajor_client_double) }
    let(:job_service_url) { 'https://bajor-host/prediction/job/123' }
    let(:prediction_options){
      {
        workflow_name: context.extractor_name,
        fixed_crop: context.metadata['fixed_crop'],
      }.compact
    }

    context 'when bajor submission succeeds' do
      before do
        allow(bajor_client_double).to receive(:create_prediction_job).and_return(job_service_url)
      end

      it 'does not raise unexpected errors' do
        expect { prediction_create_job.run }.not_to raise_error
      end

      it 'return the prediction job from the operation' do
        expect(prediction_create_job.run).to eq(prediction_job)
      end

      it 'calls the bajor client service to create a prediction job' do
        prediction_create_job.run
        expect(bajor_client_double).to have_received(:create_prediction_job).with(manifest_url, prediction_options).once
      end

      describe 'prediction_job with active_subject_set_id' do
        let(:context){ contexts(:galaxy_zoo_euclid_active_learning_project) }
        let(:prediction_job) do
          PredictionJob.new(
            manifest_url: manifest_url,
            state: :pending,
            subject_set_id: context.active_subject_set_id,
            probability_threshold: 0.5,
            randomisation_factor: 0.5
          )
        end

        it 'calls the bajor client service with workflow name from active_subject_set_id' do
          described_class.new(prediction_job, bajor_client_double).run
          expect(bajor_client_double).to have_received(:create_prediction_job).with(manifest_url, prediction_options).once
        end
      end

      it 'updates the state tracking info on the prediction job resource' do
        expect {
          prediction_create_job.run
        }.to change(prediction_job, :service_job_url).from('').to(job_service_url)
         .and change(prediction_job, :state).from('pending').to('submitted')
      end
    end

    context 'when bajor submission fails' do
      let(:error_message) { 'some error state message' }

      before do
        allow(bajor_client_double).to receive(:create_prediction_job).and_raise(Bajor::Client::Error, error_message)
      end

      it 'stores the error message on the prediction job resource' do
        expect {
          prediction_create_job.run
        }.to change(prediction_job, :state).from('pending').to('failed')
         .and change(prediction_job, :message).from('').to(error_message)
      end
    end
  end
end
