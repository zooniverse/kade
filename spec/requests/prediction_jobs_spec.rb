# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PredictionJobs', type: :request do
  let(:request_headers) do
    json_headers_with_basic_auth(
      Rails.application.config.api_basic_auth_username,
      Rails.application.config.api_basic_auth_password
    )
  end
  let(:manifest_url) { 'https://manifest-host.zooniverse.org/manifest.csv' }
  let(:prediction_job) do
    PredictionJob.create(manifest_url: manifest_url, state: :pending, subject_set_id: 1, probability_threshold: 0.5, randomisation_factor: 0.5)
  end

  describe 'GET /prediction_jobs/:id' do
    let(:get_request) do
      get "/prediction_jobs/#{prediction_job.id}", headers: request_headers
    end

    it 'returns the ok response' do
      get_request
      expect(response).to have_http_status(:ok)
    end

    it 'serializes the correct resource response body' do
      get_request
      expected_attributes = {
        'id' => prediction_job.id,
        'state' => prediction_job.state,
        'manifest_url' => prediction_job.manifest_url,
        'service_job_url' => '',
        'message' => ''
      }
      expect(json_parsed_response_body).to include(expected_attributes)
    end

    context 'with invalid authentication credentials' do
      let(:request_headers) do
        json_headers_with_basic_auth('unknown', 'credentials')
      end

      it 'returns unauthorized response' do
        get_request
        expect(response.status).to eq(401)
      end
    end

    context 'without an authorization header' do
      let(:request_headers) { json_headers }

      it 'returns unauthorized response' do
        get_request
        expect(response.status).to eq(401)
      end
    end
  end

  describe 'GET /prediction_jobs/' do
    before do
      prediction_job
    end

    it 'returns the ok response' do
      get '/prediction_jobs/', headers: request_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns the prediciton job records' do
      get '/prediction_jobs/', headers: request_headers
      expect(json_parsed_response_body.length).to eq(1)
    end
  end

  describe 'POST /prediction_jobs/' do
    let(:unwrapped_payload) do
      {
        manifest_url: manifest_url
      }
    end
    let(:json_payload) do
      { prediction_job: unwrapped_payload }.to_json
    end
    let(:create_request) { post '/prediction_jobs', params: json_payload, headers: request_headers }
    let(:submissions_job_service_double) { instance_double(PredictionJobSubmissionJob) }
    let(:prediciton_job_result) { PredictionJob.new(id: -1) }

    fixtures :contexts

    before do
      allow(ENV).to receive(:fetch).and_call_original # ensure we preserve the behavious of other ENV vars
      allow(ENV).to receive(:fetch).with('ZOOBOT_GZ_CONTEXT_ID').and_return('1')
      allow(submissions_job_service_double).to receive(:perform).and_return(prediciton_job_result)
      allow(PredictionJobSubmissionJob).to receive(:new).and_return(submissions_job_service_double)
    end

    it 'creates a PredictionJob resource' do
      expect { create_request }.to change(PredictionJob, :count).by(1)
    end

    it 'creates the PredictionJob resource with default values' do
      allow(PredictionJob).to receive(:create!).and_return(prediciton_job_result)
      create_request
      expected_attributes = { manifest_url: manifest_url, state: :pending, probability_threshold: 0.8, randomisation_factor: 0.2, subject_set_id: 55}.stringify_keys
      expect(PredictionJob).to have_received(:create!).with(expected_attributes)
    end

    it 'returns the created response' do
      create_request
      expect(response).to have_http_status(:created)
    end

    it 'serailizes the created prediction job in the response body as json' do
      create_request
      expected_attributes = %w[created_at id manifest_url message results_url service_job_url state probability_threshold randomisation_factor subject_set_id updated_at context_id catalogue_snapshot selection applied_at]
      expect(json_parsed_response_body.keys).to match_array(expected_attributes)
    end

    it 'attempts to submit the job in the request' do
      create_request
      expect(submissions_job_service_double).to have_received(:perform)
    end

    context 'when the job fails to submit to the prediction service' do
      before do
        allow(submissions_job_service_double).to receive(:perform).and_raise(PredictionJobSubmissionJob::Failure)
      end

      it 'backgrounds the job submission if there is a failure' do
        allow(PredictionJobSubmissionJob).to receive(:perform_async)
        create_request
        expect(PredictionJobSubmissionJob).to have_received(:perform_async)
      end
    end

    context 'with optional params' do
      let(:unwrapped_payload) do
        {
          manifest_url: manifest_url,
          probability_threshold: 0.8,
          randomisation_factor: 0.2,
          subject_set_id: '1'
        }
      end
      let(:expected_params) do
        { manifest_url: manifest_url, state: :pending, probability_threshold: 0.8, randomisation_factor: 0.2, subject_set_id: '1' }.stringify_keys
      end

      it 'creates the prediction job with the optional params' do
        allow(PredictionJob).to receive(:create!).and_return(prediciton_job_result)
        create_request
        expect(PredictionJob).to have_received(:create!).with(expected_params)
      end
    end

    context 'with unrwapped params' do
      let(:json_payload) do
        unwrapped_payload.to_json
      end

      it 'returns the created response' do
        create_request
        expect(response).to have_http_status(:created)
      end
    end

    context 'with invalid authentication credentials' do
      let(:request_headers) do
        json_headers_with_basic_auth('unknown', 'credentials')
      end

      it 'returns unauthorized response' do
        create_request
        expect(response.status).to eq(401)
      end
    end

    context 'without an authorization header' do
      let(:request_headers) { json_headers }

      it 'returns unauthorized response' do
        create_request
        expect(response.status).to eq(401)
      end
    end
  end
end
