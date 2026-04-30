# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RetrainZoobotJob, type: :job do
  describe 'perform' do
    fixtures :contexts

    let(:job) { described_class.new }
    let(:context) { Context.first }
    let(:export_training_data_double) { instance_double(Export::TrainingData) }
    let(:batch_training_create_job_double) { instance_double(Batch::Training::CreateJob) }
    let(:training_job) { TrainingJob.new(id: -1) }

    before do
      allow(export_training_data_double).to receive(:run)
      allow(Export::TrainingData).to receive(:new).and_return(export_training_data_double)
      allow(batch_training_create_job_double).to receive(:run).and_return(training_job)
      allow(TrainingJob).to receive(:create!).and_call_original
      allow(Honeybadger).to receive(:notify)
      allow(Batch::Training::CreateJob).to receive(:new).with(instance_of(TrainingJob)).and_return(batch_training_create_job_double)
    end

    it 'creates the training data export resource' do
      expect { job.perform(context.id) }.to change(TrainingDataExport, :count).by(1)
    end

    it 'runs the training data export service' do
      job.perform(context.id)
      expect(export_training_data_double).to have_received(:run).once
    end

    it 'creates the training job resource for monitoring' do
      job.perform(context.id)
      expect(TrainingJob).to have_received(:create!).once
    end

    it 'runs the batch training create job service' do
      job.perform(context.id)
      expect(batch_training_create_job_double).to have_received(:run).once
    end

    it 'queues a TrainingJobMonitorJob in the background' do
      allow(TrainingJobMonitorJob).to receive(:perform_in)
      job.perform(context.id)
      expect(TrainingJobMonitorJob).to have_received(:perform_in).with(10.minutes, training_job.id, context.id)
    end

    context 'when the training job failed to submit' do
      before do
        allow(training_job).to receive(:failed?).and_return(true)
      end

      it 'does not queue a TrainingJobMonitorJob in the background if job fails to submit', :aggregate_failures do
        allow(TrainingJobMonitorJob).to receive(:perform_in)
        expect { job.perform(context.id) }.to raise_error(RetrainZoobotJob::Failure)
        expect(TrainingJobMonitorJob).not_to have_received(:perform_in)
      end

      it 'notifies Honeybadger about the failed training job' do
        expect { job.perform(context.id) }.to raise_error(RetrainZoobotJob::Failure)
        expect(Honeybadger).to have_received(:notify).with(instance_of(RetrainZoobotJob::Failure))
      end
    end

    context 'when training data export fails' do
      let(:export_error) { Format::TrainingDataCsv::MissingLocationData.new('For subject id: 1') }

      before do
        allow(export_training_data_double).to receive(:run).and_raise(export_error)
      end

      it 'notifies Honeybadger before reraising' do
        expect { job.perform(context.id) }.to raise_error(Format::TrainingDataCsv::MissingLocationData)

        expect(Honeybadger).to have_received(:notify).with(export_error)
      end
    end

    context 'with existing training data exports' do
      it 'finds and reuses the existing training data export created less than 12 hours ago' do
        training_data_export = TrainingDataExport.create!(workflow_id: context.workflow_id, created_at: 11.hours.ago, storage_path: 'test', state: :finished)
        expect(job.find_recent_training_data_export(context.workflow_id)).to eq(training_data_export)
      end

      it 'does not find or reuse an existing training data export created more than 12 hours ago' do
        TrainingDataExport.create!(workflow_id: context.workflow_id, created_at: (12.hours + 1.minute).ago, storage_path: 'test', state: :finished)
        expect(job.find_recent_training_data_export(context.workflow_id)).to be_nil
      end
    end
  end
end
