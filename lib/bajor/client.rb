# frozen_string_literal: true

require 'httparty'

module Bajor
  class Client
    class Error < StandardError; end
    class PredictionJobTaskError < StandardError; end
    class TrainingJobTaskError < StandardError; end

    JSON_HEADERS = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }.freeze
    DEFAULT_OPTIONS = { workflow_name: 'cosmic_dawn' }.freeze

    include HTTParty

    default_timeout 15

    base_uri ENV.fetch('BAJOR_API_URL', 'https://bajor.zooniverse.org')

    basic_auth ENV.fetch('BAJOR_BASIC_AUTH_USERNAME', 'bajor'), ENV.fetch('BAJOR_BASIC_AUTH_PASSWORD', 'bajor')

    BLOB_STORE_HOST_CONTAINER_URL = 'https://kadeactivelearning.blob.core.windows.net'

    def create_training_job(manifest_path, training_opts = {})
      bajor_response = self.class.post(
        '/training/jobs/',
        # NOTE: Here we can augment the batch job run options via bajor
        # via the `run_opts: '--wandb --debug'` etc, these could be set via ENV
        body: { manifest_path: manifest_path, opts: build_opts(training_opts) }.to_json,
        headers: JSON_HEADERS
      )

      # bajor returns 201 on successful submission
      raise_error(bajor_response) if bajor_response.code != 201

      # return a bajor job tracking service URL
      bajor_training_job_tracking_url(bajor_response['id'])
    end

    def create_prediction_job(manifest_url, prediction_opts = {})
      bajor_response = self.class.post(
        '/prediction/jobs/',
        body: { manifest_url: manifest_url, opts: build_opts(prediction_opts) }.to_json,
        headers: JSON_HEADERS
      )

      # bajor returns 201 on successful submission
      raise_error(bajor_response) if bajor_response.code != 201

      # return a bajor job tracking service URL
      bajor_prediction_job_tracking_url(bajor_response['id'])
    end

    def prediction_job_results(job_id)
      bajor_response = self.class.get("/prediction/job/#{job_id}", headers: JSON_HEADERS)

      # bajor returns 200 on successful submission
      # anything else here will raise for notification at the callsite
      raise_error(bajor_response) if bajor_response.code != 200

      # loop over the task responses to collect the task results
      all_tasks_results = bajor_response['tasks'].map do |task|
        task.dig('execution_info', 'result')
      end

      if all_tasks_results.all?('success') # all tasks done and all good
        job_results_env_setting = bajor_response['common_environment_settings'].find do |env_setting|
          env_setting['name'] == 'PREDICTIONS_JOB_RESULTS_DIR'
        end
        # construct the prediction job results url - this could move to the bajor create prediction job api response
        job_results_path_suffix = job_results_env_setting['value']
        "#{BLOB_STORE_HOST_CONTAINER_URL}/predictions/#{job_results_path_suffix}/predictions.json"
      elsif all_tasks_results.any?('failure') # one of the tasks failed :(
        message = "One or more prediction job tasks failed - see job log details from: #{self.class.base_uri}/prediction/job/#{job_id}"
        raise(PredictionJobTaskError, message)
      elsif all_tasks_results.any?(&:nil?) # tasks are still running
        nil
      end
    end

    def training_job_results(job_id)
      bajor_response = self.class.get("/training/job/#{job_id}", headers: JSON_HEADERS)

      # bajor returns 200 on successful submission
      # anything else here will raise for notification at the callsite
      raise_error(bajor_response) if bajor_response.code != 200

      # loop over the task responses to collect the task results
      all_tasks_results = bajor_response['tasks'].map do |task|
        task.dig('execution_info', 'result')
      end

      if all_tasks_results.all?('success') # all tasks done and all good
        job_results_env_setting = bajor_response['common_environment_settings'].find do |env_setting|
          env_setting['name'] == 'TRAINING_JOB_RESULTS_DIR'
        end
        # construct the training job results directory url
        # this doesn't include a model checkpoint file path
        # as we don't know the specific file name as it's constructed by the training system
        # including values like loss and epoch
        # see https://github.com/zooniverse/bajor/blob/66380956513db525b96e352557a35ae2e0b7e76d/azure/batch/scripts/train_model_finetune_on_catalog.py#L70
        # so using the directory here is good enough for now
        job_results_path_suffix = job_results_env_setting['value']
        "#{BLOB_STORE_HOST_CONTAINER_URL}/training/#{job_results_path_suffix}/"
      elsif all_tasks_results.any?('failure') # one of the tasks failed :(
        message = "One or more prediction job tasks failed - see job log details from: #{self.class.base_uri}/training/job/#{job_id}"
        raise(TrainingJobTaskError, message)
      elsif all_tasks_results.any?(&:nil?) # tasks are still running
        nil
      end
    end

    private

    def raise_error(bajor_response)
      # bajor may return a json object with message body
      msg = bajor_response['message']
      # failing that let's try and craft a decent error message from the httparty response error
      msg ||= "Failed with response code: #{bajor_response.response.code} - #{bajor_response.response.message}"

      # most likely a 409 conflict error (limit of active jobs reached)
      # but could be a missing URL or service issue error (500) etc
      raise(Error, msg)
    end

    def bajor_training_job_tracking_url(submitted_job_id)
      "#{bajor_service_host}/training/job/#{submitted_job_id}"
    end

    def bajor_prediction_job_tracking_url(submitted_job_id)
      "#{bajor_service_host}/prediction/job/#{submitted_job_id}"
    end

    def bajor_service_host
      service_host_suffix = Rails.env.staging? ? '-staging' : ''
      "https://bajor#{service_host_suffix}.zooniverse.org"
    end

    def build_opts(options)
      raw = options.with_indifferent_access
      overrides = raw.symbolize_keys.slice(:workflow_name, :fixed_crop)

      DEFAULT_OPTIONS
      .merge(overrides)
      .compact.tap do |o|
        o[:run_opts] = "--schema #{o[:workflow_name].downcase}"
        if o[:fixed_crop].present?
          o[:run_opts] += " --fixed_crop #{o[:fixed_crop].to_json}"
          o.delete(:fixed_crop)
        end
      end
    end
  end
end
