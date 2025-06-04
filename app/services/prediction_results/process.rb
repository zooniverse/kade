# frozen_string_literal: true

require 'remote_file/reader'

module PredictionResults
  class Process
    SUBJECT_ACTION_API_BATCH_SIZE = ENV.fetch('SUBJECT_ACTION_API_BATCH_SIZE', '10').to_i
    COMPLETION_NOTIFICATION_THRESHOLD = ENV.fetch('COMPLETION_NOTIFICATION_THRESHOLD', '0.95').to_f

    attr_accessor :results_url, :subject_set_id, :probability_threshold,
                  :over_threshold_subject_ids, :under_threshold_subject_ids,
                  :random_spice_subject_ids, :randomisation_factor, :prediction_data

    def initialize(results_url:, subject_set_id:, probability_threshold: 0.8, randomisation_factor: 0.2)
      @results_url = results_url
      @subject_set_id = subject_set_id
      @probability_threshold = probability_threshold
      @randomisation_factor = randomisation_factor
      @over_threshold_subject_ids = []
      @under_threshold_subject_ids = []
      @random_spice_subject_ids = []
      @prediction_data = nil
      @total_subjects = 0
    end

    def run
      # paritions the data by specified probability threshold
      RemoteFile::Reader.stream_to_tempfile(results_url) do |results_file|
        # read the prediciton json data from the tempfile
        prediction_data_results = JSON.parse(results_file.read)
        @prediction_data = prediction_data_results['data']
        partition_results
        # TODO: ensure the resulting sets are mutually exclusive to avoid
        # running more jobs / API calls than needed
        # e.g. remove under threshold ids may conflict with the add random ones
        # do a set diff operation to ensure we don't add the same subject ids
        move_over_threshold_subjects_to_active_set
        remove_under_threshold_subjects_from_active_set
        add_random_spice_subjects_to_active_set
      end
    end

    def partition_results
      @total_subjects = prediction_data.count
      prediction_data.each do |subject_id, prediction_samples|
        # data schema format is published in the file
        # and https://github.com/zooniverse/bajor/blob/main/azure/batch/scripts/predict_on_catalog.py
        # the hash is keyed by the sample_num
        # we will use the the first sample for the prediction results
        prediction_results = prediction_samples['0']
        # and we want the probability from the first entry in the prediction results array
        probability = prediction_results[0]
        @over_threshold_subject_ids << subject_id if probability >= probability_threshold
        @under_threshold_subject_ids << subject_id if probability < probability_threshold
      end
      check_completion_and_notify
      # now add some 'spice' to the results by adding some random under threshold subject ids
      # but don't skew the prediction results by adding too many under threshold images
      # ensure we only use apply the randomisation factor to the count of over threshold subject ids
      # i.e. 20% of the number of over threshold subject ids
      num_random_subject_ids_to_sample = (over_threshold_subject_ids.count * randomisation_factor).to_i
      @random_spice_subject_ids = under_threshold_subject_ids.sample(num_random_subject_ids_to_sample)

      # ensure the random subject ids aren't in the under_threshold_subject_ids list
      @under_threshold_subject_ids = under_threshold_subject_ids - random_spice_subject_ids
    end

    def move_over_threshold_subjects_to_active_set
      AddSubjectToSubjectSetJob.perform_bulk(
        api_batch_bulk_job_args(over_threshold_subject_ids)
      )
    end

    def remove_under_threshold_subjects_from_active_set
      RemoveSubjectFromSubjectSetJob.perform_bulk(
        api_batch_bulk_job_args(under_threshold_subject_ids)
      )
    end

    def add_random_spice_subjects_to_active_set
      AddSubjectToSubjectSetJob.perform_bulk(
        api_batch_bulk_job_args(random_spice_subject_ids)
      )
    end

    def api_batch_bulk_job_args(subject_ids)
      subject_ids
        .each_slice(SUBJECT_ACTION_API_BATCH_SIZE)
        .map { |batch_subject_ids| [batch_subject_ids, subject_set_id] }
    end

    private
    def check_completion_and_notify
      total_under_threshold_subjects = @under_threshold_subject_ids.count
      completion_rate = (total_under_threshold_subjects.to_f / @total_subjects.to_f)
      if completion_rate >= COMPLETION_NOTIFICATION_THRESHOLD
        NotifyProjectOwnerJob.perform_async(subject_set_id, completion_rate)
      end
    end
  end
end
