# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin resource pages', type: :request do
  fixtures :contexts

  let(:context) { contexts(:galaxy_zoo_cosmos_active_learning_project) }
  let(:request_headers) do
    {
      'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials(
        Rails.application.config.admin_basic_auth_username,
        Rails.application.config.admin_basic_auth_password
      )
    }
  end

  describe 'subjects' do
    it 'renders the subjects index and show pages' do
      subject = Subject.create!(
        zooniverse_subject_id: 900001,
        context: context,
        metadata: { source: 'test' },
        locations: [{ 'image/jpeg' => 'https://example.com/image.jpg' }]
      )

      get '/admin/subjects', headers: request_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Subjects')
      expect(response.body).to include(subject.zooniverse_subject_id.to_s)

      get "/admin/subjects/#{subject.id}", headers: request_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Subject #{subject.id}")
      expect(response.body).to include('source')
    end

    it 'paginates the subjects index' do
      26.times do |index|
        Subject.create!(
          zooniverse_subject_id: 910_000 + index,
          context: context,
          metadata: {},
          locations: []
        )
      end

      get '/admin/subjects', params: { page_size: 25 }, headers: request_headers
      expect(response.body).to include('Page 1 of 2')
      expect(response.body).to include('910025')

      get '/admin/subjects', params: { page: 2, page_size: 25 }, headers: request_headers
      expect(response.body).to include('Page 2 of 2')
      expect(response.body).not_to include('910025')
      expect(response.body).to include('910000')
    end
  end

  describe 'training data exports' do
    it 'renders the training data exports index and show pages' do
      export = TrainingDataExport.create!(
        workflow_id: 5001,
        storage_path: '/training/export.csv',
        state: :started
      )

      get '/admin/training_data_exports', headers: request_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Training Data Exports')
      expect(response.body).to include(export.workflow_id.to_s)

      get "/admin/training_data_exports/#{export.id}", headers: request_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Training Data Export #{export.id}")
      expect(response.body).to include('/training/export.csv')
    end
  end

  describe 'reductions' do
    it 'renders the reductions index and show pages' do
      subject = Subject.create!(
        zooniverse_subject_id: 920001,
        context: context,
        metadata: {},
        locations: []
      )
      reduction = Reduction.create!(
        subject: subject,
        workflow_id: context.workflow_id,
        zooniverse_subject_id: subject.zooniverse_subject_id,
        labels: { smooth: 3 },
        raw_payload: { data: { '0' => 3 } },
        unique_id: 'reduction-1',
        task_key: 'T0'
      )

      get '/admin/reductions', headers: request_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Reductions')
      expect(response.body).to include(reduction.zooniverse_subject_id.to_s)

      get "/admin/reductions/#{reduction.id}", headers: request_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Reduction #{reduction.id}")
      expect(response.body).to include('smooth')
    end
  end

  describe 'prediction jobs' do
    it 'renders the prediction jobs index and show pages' do
      prediction_job = PredictionJob.create!(
        manifest_url: 'https://example.com/predictions.csv',
        state: 'pending',
        subject_set_id: 123,
        probability_threshold: 0.8,
        randomisation_factor: 0.2
      )

      get '/admin/prediction_jobs', headers: request_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Prediction Jobs')
      expect(response.body).to include(prediction_job.subject_set_id.to_s)

      get "/admin/prediction_jobs/#{prediction_job.id}", headers: request_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Prediction Job #{prediction_job.id}")
      expect(response.body).to include('https://example.com/predictions.csv')
    end
  end

  describe 'training jobs' do
    it 'renders the training jobs index and show pages' do
      training_job = TrainingJob.create!(
        manifest_url: 'https://example.com/training.csv',
        state: 'pending',
        workflow_id: 7001
      )

      get '/admin/training_jobs', headers: request_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Training Jobs')
      expect(response.body).to include(training_job.workflow_id.to_s)

      get "/admin/training_jobs/#{training_job.id}", headers: request_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Training Job #{training_job.id}")
      expect(response.body).to include('https://example.com/training.csv')
    end
  end

  describe 'context manual triggers' do
    it 'queues a prediction job trigger from the context page' do
      allow(PredictionManifestExportJob).to receive(:perform_async).with(context.id).and_return('prediction-jid-123')

      post "/admin/contexts/#{context.id}/trigger_prediction_job", headers: request_headers

      expect(response).to redirect_to("/admin/contexts/#{context.id}")
      get "/admin/contexts/#{context.id}", headers: request_headers

      expect(response.body).to include('Prediction job trigger queued')
      expect(PredictionManifestExportJob).to have_received(:perform_async).with(context.id).once
    end

    it 'queues a training job trigger from the context page' do
      allow(RetrainZoobotJob).to receive(:perform_async).with(context.id).and_return('training-jid-123')

      post "/admin/contexts/#{context.id}/trigger_training_job", headers: request_headers

      expect(response).to redirect_to("/admin/contexts/#{context.id}")
      get "/admin/contexts/#{context.id}", headers: request_headers

      expect(response.body).to include('Training job trigger queued')
      expect(RetrainZoobotJob).to have_received(:perform_async).with(context.id).once
    end
  end
end
