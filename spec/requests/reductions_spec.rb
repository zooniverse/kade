# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reductions', type: :request do
  fixtures :contexts

  let(:context) { Context.first }
  let(:non_create_request_headers) do
    json_headers_with_basic_auth(
      Rails.application.config.api_basic_auth_username,
      Rails.application.config.api_basic_auth_password
    )
  end
  let(:create_request_headers) do
    json_headers_with_basic_auth(
      Rails.application.config.reduction_basic_auth_username,
      Rails.application.config.reduction_basic_auth_password
    )
  end
  let(:subject_instance) do
    Subject.create(zooniverse_subject_id: 999, context_id: context.id)
  end
  let(:reduction) do
    Reduction.create(
      {
        zooniverse_subject_id: subject_instance.zooniverse_subject_id,
        subject_id: subject_instance.id,
        workflow_id: context.workflow_id,
        labels: {},
        unique_id: 'very_unique_id',
        task_key: 'T0'
      }
    )
  end

  before do
    subject_instance
  end

  describe 'GET /reductions/:id' do
    let(:get_request) do
      get "/reductions/#{reduction.id}", headers: non_create_request_headers
    end

    it 'returns the ok response' do
      get_request
      expect(response).to have_http_status(:ok)
    end

    it 'serializes the json subject data in the response body' do
      get_request
      expected_attributes = {
        'id' => reduction.id,
        'zooniverse_subject_id' => reduction.zooniverse_subject_id,
        'labels' => reduction.labels,
        'unique_id' => reduction.unique_id
      }
      expect(json_parsed_response_body).to include(expected_attributes)
    end

    it 'serializes the linked subject json data in the response body' do
      get_request
      expect(json_parsed_response_body['subject']).not_to be_empty
    end

    context 'with invalid authentication credentials' do
      let(:non_create_request_headers) do
        json_headers_with_basic_auth('unknown', 'credentials')
      end

      it 'returns unauthorized response' do
        get_request
        expect(response.status).to eq(401)
      end
    end

    context 'without an authorization header' do
      let(:non_create_request_headers) { json_headers }

      it 'returns unauthorized response' do
        get_request
        expect(response.status).to eq(401)
      end
    end
  end

  describe 'GET /reductions/' do
    before do
      reduction
    end

    it 'returns the ok response' do
      get '/reductions/', headers: non_create_request_headers
      expect(response).to have_http_status(:ok)
    end

    it 'returns both subject records' do
      get '/reductions/', headers: non_create_request_headers
      expect(json_parsed_response_body.length).to eq(1)
    end

    it 'filters via the ?zooniverse_subject_id param' do
      other_reduction = Reduction.create(
        { zooniverse_subject_id: 1001, subject_id: -1, workflow_id: context.workflow_id, unique_id: 'more-unique', task_key: 'T0' }
      )
      get "/reductions/?zooniverse_subject_id=#{other_reduction.zooniverse_subject_id}", headers: non_create_request_headers
      expect(json_parsed_response_body.length).to eq(1)
    end
  end

  describe 'POST /reductions/:task_schema_lookup_key' do
    let(:unwrapped_reduction_payload) do
      {
        id: 4,
        reducible: {
          id: context.workflow_id,
          type: 'Workflow'
        },
        data: {
          '0' => 3,
          '1' => 9,
          '2' => 0
        },
        subject: {
          id: 999,
          metadata: { '#name' => '8000_231121_468' },
          created_at: '2021-08-06T11:08:53.918Z',
          updated_at: '2021-08-06T11:08:53.918Z'
        },
        reducer_key: 'caesar-reducer-id',
        created_at: '2021-08-06T11:08:54.000Z',
        updated_at: '2021-08-06T11:08:54.000Z'
      }
    end
    let(:reduction_json_payload) do
      { reduction: unwrapped_reduction_payload }.to_json
    end
    let(:create_request) { post '/reductions/galaxy_zoo_cosmic_dawn_t0', params: reduction_json_payload, headers: create_request_headers }

    it 'returns the created response' do
      create_request
      expect(response).to have_http_status(:created)
    end

    it 'serailizes the created reduction in the response body as json' do
      create_request
      expected_attributes = %w[id zooniverse_subject_id subject_id workflow_id labels raw_payload unique_id task_key created_at updated_at]
      expect(json_parsed_response_body.keys).to match_array(expected_attributes)
    end

    context 'with unrwapped params' do
      let(:reduction_json_payload) do
        unwrapped_reduction_payload.to_json
      end

      it 'returns the created response' do
        create_request
        expect(response).to have_http_status(:created)
      end
    end

    context 'with a DB-backed label extractor definition' do
      let(:context) do
        Context.create!(
          workflow_id: 555,
          project_id: 42,
          active_subject_set_id: 501,
          pool_subject_set_id: 502,
          module_name: 'new_project',
          extractor_name: 'main'
        )
      end
      let(:create_request) { post '/reductions/new_project_main_t0', params: reduction_json_payload, headers: create_request_headers }

      before do
        LabelExtractorDefinition.create!(
          module_name: 'new_project',
          extractor_name: 'main',
          config: {
            data_release_suffix: 'np',
            task_key_label_prefixes: { T0: 'smooth-or-featured' },
            task_key_data_labels: {
              T0: {
                '0': 'smooth',
                '1': 'featured',
                '2': 'artifact'
              }
            }
          }
        )
      end

      it 'creates a reduction using configurable labels' do
        create_request

        expect(response).to have_http_status(:created)
        expect(json_parsed_response_body['labels']).to eq(
          'smooth-or-featured-np_smooth' => 3,
          'smooth-or-featured-np_featured' => 9,
          'smooth-or-featured-np_artifact' => 0
        )
      end
    end

    context 'with invalid authentication credentials' do
      let(:create_request_headers) do
        json_headers_with_basic_auth('unknown', 'credentials')
      end

      it 'returns unauthorized response' do
        create_request
        expect(response.status).to eq(401)
      end
    end

    context 'without an authorization header' do
      let(:create_request_headers) { json_headers }

      it 'returns unauthorized response' do
        create_request
        expect(response.status).to eq(401)
      end
    end
  end
end
