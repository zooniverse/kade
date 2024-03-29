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
      allow(PredictionJobSubmissionJob).to receive(:perform_async)
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
  end
end
