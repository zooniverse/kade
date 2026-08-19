# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrainingJobMonitorJob, type: :job do
  describe 'perform' do
    fixtures :contexts

    let(:training_job) do
      TrainingJob.create(
        service_job_url: 'https://bajor-staging.zooniverse.org/training/job/64bf4fab-ed6d-4f9a-b8ae-004086e3676f',
        manifest_url: 'https://manifest-host/manifest.csv',
        state: :submitted,
        workflow_id: 1
      )
    end
    let(:training_job_monitor_result) { TrainingJob.new(id: -1) }
    let(:training_job_monitor_service) { instance_double(Batch::Training::MonitorJob) }
    let(:context) { Context.first }
    let(:job) { described_class.new }

    before do
      allow(training_job_monitor_service).to receive(:run).and_return(training_job_monitor_result)
      allow(Batch::Training::MonitorJob).to receive(:new).and_return(training_job_monitor_service)
      allow(training_job).to receive(:completed?).and_return(false)
    end

    it 'runs the training job monitor service' do
      job.perform(training_job.id, context.id)
      expect(training_job_monitor_service).to have_received(:run)
    end

    it 'reschedules itself if the job has not fininshed' do
      allow(training_job_monitor_result).to receive(:completed?).and_return(false)
      allow(described_class).to receive(:perform_in)
      job.perform(training_job.id, context.id)
      expect(described_class).to have_received(:perform_in).with(1.minute, training_job_monitor_result.id, context.id)
    end

    context 'when the monitor job returns a completed job' do
      before do
        allow(training_job_monitor_result).to receive(:completed?).and_return(true)
        allow(training_job_monitor_result).to receive(:workflow_id).and_return(1)
        allow(PredictionManifestExportJob).to receive(:perform_async).and_return('prediction-manifest-export-job-id')
        allow(Honeybadger).to receive(:notify)
      end

      it 'schedules a process prediction creation job with the correct pool_subject_set_id' do
        job.perform(training_job.id, context.id)
        expect(PredictionManifestExportJob).to have_received(:perform_async).with(context.id)
      end

      it 'does not reschedule the monitor job' do
        allow(described_class).to receive(:perform_in)
        job.perform(training_job.id, context.id)
        expect(described_class).not_to have_received(:perform_in)
      end

      it 'does not notify Honeybadger when the prediction manifest export job is queued' do
        job.perform(training_job.id, context.id)
        expect(Honeybadger).not_to have_received(:notify)
      end

      it 'notifies Honeybadger when the prediction manifest export job is not queued' do
        allow(PredictionManifestExportJob).to receive(:perform_async).and_return(nil)
        job.perform(training_job.id, context.id)
        expect(Honeybadger).to have_received(:notify).with(
          an_object_having_attributes(
            message: 'TrainingJobMonitorJob did not enqueue PredictionManifestExportJob'
          ),
          context: { current_step: 'enqueue_prediction_manifest_export_job' }
        )
      end

      it 'notifies Honeybadger when queuing the prediction manifest export job raises' do
        allow(PredictionManifestExportJob).to receive(:perform_async).and_raise(StandardError, 'redis failed')

        expect { job.perform(training_job.id, context.id) }.to raise_error(StandardError, 'redis failed')

        expect(Honeybadger).to have_received(:notify).with(
          an_object_having_attributes(message: 'redis failed'),
          context: { current_step: 'enqueue_prediction_manifest_export_job' }
        )
      end
    end

    context 'when the monitor job returns a failure :(' do
      before do
        allow(training_job_monitor_result).to receive(:completed?).and_return(false)
        allow(training_job_monitor_result).to receive(:failed?).and_return(true)
      end

      it 'does not reschedule the monitor job' do
        allow(described_class).to receive(:perform_in)
        job.perform(training_job.id, context.id)
        expect(described_class).not_to have_received(:perform_in)
      end

      it 'reports the failure error to HB' do
        allow(Honeybadger).to receive(:notify)
        job.perform(training_job.id, context.id)
        expect(Honeybadger).to have_received(:notify).with(instance_of(TrainingJobMonitorJob::TrainingFailure))
      end
    end

    context 'when the training job has been already completed' do
      before do
        training_job.update_column(:state, 'completed')
      end

      it 'does not run the training job monitor service' do
        job.perform(training_job.id, context.id)
        expect(training_job_monitor_service).not_to have_received(:run)
      end
    end
  end
end
