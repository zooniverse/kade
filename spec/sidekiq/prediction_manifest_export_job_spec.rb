# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PredictionManifestExportJob, type: :job do
  describe 'perform' do
    fixtures :contexts

    let(:export_manifest_double) { instance_double(Batch::Prediction::ExportManifest, manifest_url: 'https://manifest/path.json') }
    let(:context) { Context.first }
    let(:active_subject_set_id) { context.active_subject_set_id }
    let(:pool_subject_set_id) { context.pool_subject_set_id }
    let(:context_double) { instance_double(Context, active_subject_set_id: active_subject_set_id, pool_subject_set_id: pool_subject_set_id) }
    let(:job) { described_class.new }

    before do
      allow(ENV).to receive(:fetch).and_call_original # ensure we preserve the behavious of other ENV vars
      allow(ENV).to receive(:fetch).with('ZOOBOT_GZ_CONTEXT_ID').and_return('-1')
      allow(export_manifest_double).to receive(:run)
      allow(Batch::Prediction::ExportManifest).to receive(:new).and_return(export_manifest_double)
      allow(Context).to receive(:find).and_return(context_double)
      allow(PredictionJob).to receive(:create!).and_call_original
      allow(PredictionJobSubmissionJob).to receive(:perform_async).and_return('submission-job-id')
      allow(Honeybadger).to receive(:notify)
    end

    it 'runs the prediction manifest export service' do
      job.perform(context.id)
      expect(export_manifest_double).to have_received(:run)
    end

    it 'creates a prediction job resource' do
      job.perform(context.id)
      create_args = { state: :pending, manifest_url: export_manifest_double.manifest_url, subject_set_id: active_subject_set_id, probability_threshold: 0.8, randomisation_factor: 0.2 }
      expect(PredictionJob).to have_received(:create!).with(create_args)
    end

    it 'submits the prediction job for processing' do
      prediction_job_double = instance_double(PredictionJob, id: 1)
      allow(PredictionJob).to receive(:create!).and_return(prediction_job_double)
      job.perform(context.id)
      expect(PredictionJobSubmissionJob).to have_received(:perform_async).with(prediction_job_double.id)
    end

    it 'does not notify Honeybadger on success' do
      job.perform(context.id)
      expect(Honeybadger).not_to have_received(:notify)
    end

    context 'when the context lookup fails' do
      before do
        allow(Context).to receive(:find).and_raise(ActiveRecord::RecordNotFound)
      end

      it 'notifies Honeybadger with the failed lookup step before reraising' do
        expect { job.perform(context.id) }.to raise_error(ActiveRecord::RecordNotFound)

        expect(Honeybadger).to have_received(:notify).with(
          instance_of(ActiveRecord::RecordNotFound),
          context: { current_step: 'find_context' }
        )
      end
    end

    context 'when the manifest export fails' do
      before do
        allow(export_manifest_double).to receive(:run).and_raise(StandardError, 'manifest failed')
      end

      it 'does not duplicate the export manifest Honeybadger notification' do
        expect { job.perform(context.id) }.to raise_error(StandardError, 'manifest failed')

        expect(Honeybadger).not_to have_received(:notify)
      end
    end

    context 'when the prediction job creation fails' do
      before do
        allow(PredictionJob).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      end

      it 'notifies Honeybadger with the failed creation step before reraising' do
        expect { job.perform(context.id) }.to raise_error(ActiveRecord::RecordInvalid)

        expect(Honeybadger).to have_received(:notify).with(
          instance_of(ActiveRecord::RecordInvalid),
          context: { current_step: 'create_prediction_job' }
        )
      end
    end

    context 'when the prediction job submission is not queued' do
      before do
        allow(PredictionJobSubmissionJob).to receive(:perform_async).and_return(nil)
      end

      it 'notifies Honeybadger about the missing submission job id' do
        prediction_job_double = instance_double(PredictionJob, id: 1)
        allow(PredictionJob).to receive(:create!).and_return(prediction_job_double)
        job.perform(context.id)

        expect(Honeybadger).to have_received(:notify).with(
          an_object_having_attributes(
            message: 'PredictionManifestExportJob did not enqueue PredictionJobSubmissionJob'
          ),
          context: { current_step: 'enqueue_prediction_job_submission' }
        )
      end
    end

    context 'when the prediction job submission raises' do
      before do
        allow(PredictionJobSubmissionJob).to receive(:perform_async).and_raise(StandardError, 'redis failed')
      end

      it 'notifies Honeybadger with the failed enqueue step before reraising' do
        prediction_job_double = instance_double(PredictionJob, id: 1)
        allow(PredictionJob).to receive(:create!).and_return(prediction_job_double)

        expect { job.perform(context.id) }.to raise_error(StandardError, 'redis failed')

        expect(Honeybadger).to have_received(:notify).with(
          an_object_having_attributes(message: 'redis failed'),
          context: { current_step: 'enqueue_prediction_job_submission' }
        )
      end
    end
  end
end
