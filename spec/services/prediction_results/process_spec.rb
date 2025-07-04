# frozen_string_literal: true

require 'rails_helper'
require 'remote_file/reader'

RSpec.describe PredictionResults::Process do
  let(:confidence_threshold) { 0.8 }
  let(:remote_file) do
    # build a fake file we double as a result of the downloader
    Tempfile.new('remote-file-test')
  end
  let(:results_url) { 'https://fake.com/results.json' }
  let(:active_subject_set_id) { 1 }
  let(:process_results_service) { described_class.new(results_url: results_url, subject_set_id: active_subject_set_id) }
  let(:over_threshold_subject_id) { 1 }
  let(:under_threshold_subject_id) { 2 }
  # schema is from the bajor api prediction jobs results
  # https://github.com/zooniverse/bajor/blob/main/azure/batch/scripts/predict_on_catalog.py
  # 'data': { 'subject_id': { 'sample_num': ['probability_at_least_20pc_featured', ['smooth-or-featured-cd_smooth_prediction', 'smooth-or-featured-cd_featured-or-disk_prediction', 'smooth-or-featured-cd_problem_prediction'] ] } }
  let(:prediction_results_data) do
    {
      over_threshold_subject_id => { '0' => [0.9, [0.1, 0.1, 0.1]] }, # most likely not smooth galaxy (fake prediction data values)
      under_threshold_subject_id => { '0' => [0.1, [0.1, 0.1, 0.1]] } # most likely a smooth galaxy (fake prediction data values)
    }
  end

  before do
    remote_file.write({ data: prediction_results_data }.to_json)
    remote_file.rewind
    allow(RemoteFile::Reader).to receive(:stream_to_tempfile).and_yield(remote_file)
  end

  after do
    remote_file.close
    remote_file.unlink
  end

  describe '.run' do
    it 'downloads the remote results file for processing' do
      process_results_service.run
      expect(RemoteFile::Reader).to have_received(:stream_to_tempfile).with(results_url)
    end

    it 'partitions the results data' do
      allow(process_results_service).to receive(:partition_results)
      process_results_service.run
      expect(process_results_service).to have_received(:partition_results)
    end

    it 'moves subjects equal to or above the researcher defined probability threshold to the active set' do
      allow(process_results_service).to receive(:move_over_threshold_subjects_to_active_set)
      process_results_service.run
      expect(process_results_service).to have_received(:move_over_threshold_subjects_to_active_set)
    end

    it 'removes subjects under the researcher defined probability threshold from the active set' do
      allow(process_results_service).to receive(:remove_under_threshold_subjects_from_active_set)
      process_results_service.run
      expect(process_results_service).to have_received(:remove_under_threshold_subjects_from_active_set)
    end

    it 'adds random subjects under the probability threshold to the active set' do
      # this ensures we add variety to volunteers and keep 'normal' data in the training set so we don't overfit the model
      allow(process_results_service).to receive(:add_random_spice_subjects_to_active_set)
      process_results_service.run
      expect(process_results_service).to have_received(:add_random_spice_subjects_to_active_set)
    end
  end

  describe '#partition_results' do
    before do
      process_results_service.prediction_data = prediction_results_data
    end

    it 'correctly splits the results data via the probability_thresold', :aggregate_failures do
      process_results_service.partition_results
      expect(process_results_service.over_threshold_subject_ids).to match_array([over_threshold_subject_id])
      expect(process_results_service.under_threshold_subject_ids).to match_array([under_threshold_subject_id])
      expect(process_results_service.random_spice_subject_ids).to be_empty
    end

    it 'allows the probability_threshold to be set a runtime', :aggregate_failures do
      process_results_service.probability_threshold = 1.0
      process_results_service.partition_results
      expect(process_results_service.under_threshold_subject_ids).to match_array([over_threshold_subject_id, under_threshold_subject_id])
      expect(process_results_service.over_threshold_subject_ids).to be_empty
    end

    it 'correctly sets the random spice subject ids', :aggregate_failures do
      process_results_service.randomisation_factor = 1.0
      process_results_service.partition_results
      expect(process_results_service.over_threshold_subject_ids).to match_array([over_threshold_subject_id])
      expect(process_results_service.under_threshold_subject_ids).to be_empty
      expect(process_results_service.random_spice_subject_ids).to match_array([under_threshold_subject_id])
    end

    context 'when completion hits the notification threshold' do
      before do
        stub_const("PredictionResults::Process::COMPLETION_NOTIFICATION_THRESHOLD", 0.5)
        allow(NotifyProjectOwnerJob).to receive(:perform_async)
      end

      it 'calls NotifyProjectOwnerJob for almost retired subjects' do
        process_results_service.partition_results
        expect(NotifyProjectOwnerJob).to have_received(:perform_async).with(active_subject_set_id, 0.5)
      end
    end
  end

  describe '#move_over_threshold_subjects_to_active_set' do
    before do
      # ensure we have over threshold subjects to move
      process_results_service.over_threshold_subject_ids = [over_threshold_subject_id]
    end

    it 'calls the AddSubjectToSubjectSet worker correctly' do
      allow(AddSubjectToSubjectSetJob).to receive(:perform_bulk)
      process_results_service.move_over_threshold_subjects_to_active_set
      expect(AddSubjectToSubjectSetJob).to have_received(:perform_bulk).with([[[over_threshold_subject_id], active_subject_set_id]])
    end
  end

  describe '#remove_under_threshold_subjects_from_active_set' do
    before do
      # ensure we have under threshold subjects to remove
      process_results_service.under_threshold_subject_ids = [under_threshold_subject_id]
    end

    it 'calls the RemoveSubjectFromSubjectSet worker correctly' do
      allow(RemoveSubjectFromSubjectSetJob).to receive(:perform_bulk)
      process_results_service.remove_under_threshold_subjects_from_active_set
      expect(RemoveSubjectFromSubjectSetJob).to have_received(:perform_bulk).with([[[under_threshold_subject_id], active_subject_set_id]])
    end
  end

  describe '#add_random_under_threshold_subjects_to_active_set' do
    before do
      process_results_service.random_spice_subject_ids = [under_threshold_subject_id]
    end

    it 'calls the AddSubjectToSubjectSet worker with the sampled under threshold data' do
      allow(AddSubjectToSubjectSetJob).to receive(:perform_bulk)
      process_results_service.add_random_spice_subjects_to_active_set
      expect(AddSubjectToSubjectSetJob).to have_received(:perform_bulk).with([[[under_threshold_subject_id], active_subject_set_id]])
    end
  end
end
