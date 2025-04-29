# frozen_string_literal: true

require 'rails_helper'
require 'bajor/client'

RSpec.describe Batch::Training::CreateJob do
  describe '#run' do
    let(:manifest_path) { '/a/shared/blob/storage/path.csv' }
    let(:manifest_url) { "https://a.shared.blob.storage#{manifest_path}"}
    let(:training_job) { TrainingJob.new(manifest_url: manifest_url, workflow_id: '123', state: :pending) }
    let(:bajor_client_double) { instance_double(Bajor::Client) }
    let(:training_create_job) { described_class.new(training_job, bajor_client_double) }
    let(:job_service_url) { 'https://bajor-host/training/job/123' }

    before do
      allow(bajor_client_double).to receive(:create_training_job).and_return(job_service_url)
    end

    it 'does not raise unexpected errors' do
      expect { training_create_job.run }.not_to raise_error
    end

    it 'calls the bajor client service with the correct manifest_path' do
      parent_context = Context.find_by(workflow_id: training_job.workflow_id)
      training_opts = {
        workflow_name: parent_context.extractor_name,
        fixed_crop: parent_context.metadata['fixed_crop'],
      }.compact

      training_create_job.run
      expect(bajor_client_double).to have_received(:create_training_job).with(manifest_path, training_opts).once
    end

    it 'updates the state tracking info on the training job resource' do
      expect {
        training_create_job.run
      }.to change(training_job, :service_job_url).from('').to(job_service_url)
       .and change(training_job, :state).from('pending').to('submitted')
    end

    context 'when bajor submission fails' do
      let(:error_message) { 'some error state message' }

      before do
        allow(bajor_client_double).to receive(:create_training_job).and_raise(Bajor::Client::Error, error_message)
      end

      it 'stores the error message on the training job resource' do
        expect {
          training_create_job.run
        }.to change(training_job, :state).from('pending').to('failed')
         .and change(training_job, :message).from('').to(error_message)
      end
    end
  end
end
