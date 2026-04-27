# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Contexts', type: :request do
  fixtures :contexts

  let(:context) { contexts(:galaxy_zoo_cosmos_active_learning_project) }
  let(:request_headers) do
    json_headers_with_basic_auth(
      Rails.application.config.api_basic_auth_username,
      Rails.application.config.api_basic_auth_password
    )
  end

  describe 'PATCH /contexts/:id' do
    let(:path) { "/contexts/#{context.id}" }
    let(:runtime_config) do
      {
        container_image_name: 'zoobot.azurecr.io/pytorch:custom-euclid',
        training_script_path: 'euclid/train_model_finetune_on_catalog.py',
        prediction_script_path: 'euclid/predict_catalog_with_model.py',
        promote_script_path: 'euclid/promote_best_checkpoint_to_model.sh',
        pretrained_checkpoint_url: 'https://kadeactivelearning.blob.core.windows.net/models/euclid/euclid-pretrained.ckpt',
        n_blocks: 3,
        fixed_crop: {
          lower_left_x: 10,
          lower_left_y: 20,
          upper_right_x: 700,
          upper_right_y: 710
        }
      }
    end

    it 'updates editable context attributes' do
      patch(
        path,
        params: {
          workflow_id: 234,
          project_id: 45,
          active_subject_set_id: 58,
          pool_subject_set_id: 69,
          module_name: 'galaxy_zoo',
          extractor_name: 'euclid'
        }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:ok)

      context.reload
      expect(context.workflow_id).to eq(234)
      expect(context.project_id).to eq(45)
      expect(context.active_subject_set_id).to eq(58)
      expect(context.pool_subject_set_id).to eq(69)
      expect(context.module_name).to eq('galaxy_zoo')
      expect(context.extractor_name).to eq('euclid')
    end

    it 'accepts a DB-backed module and extractor pair' do
      LabelExtractorDefinition.create!(
        module_name: 'new_project',
        extractor_name: 'main',
        config: {
          data_release_suffix: 'np',
          task_key_label_prefixes: { T0: 'smooth-or-featured' },
          task_key_data_labels: { T0: { '0': 'smooth' } }
        }
      )

      patch(
        path,
        params: {
          module_name: 'new_project',
          extractor_name: 'main'
        }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:ok)
      expect(context.reload.module_name).to eq('new_project')
      expect(context.extractor_name).to eq('main')
    end

    it 'deep merges metadata without replacing existing metadata' do
      patch(
        path,
        params: { metadata: { model_family: 'zoobot', labels: { source: 'api' } } }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:ok)

      context.reload
      expect(context.metadata['fixed_crop']).to be_present
      expect(context.metadata['batch']).to be_present
      expect(context.metadata['model_family']).to eq('zoobot')
      expect(context.metadata.dig('labels', 'source')).to eq('api')
    end

    it 'updates context attributes and batch runtime config in the same patch' do
      patch(
        path,
        params: {
          extractor_name: 'euclid',
          metadata: { batch: runtime_config }
        }.to_json,
        headers: request_headers
      )

      expected_config = JSON.parse(runtime_config.to_json)

      expect(response).to have_http_status(:ok)
      expect(context.reload.extractor_name).to eq('euclid')
      expect(context.metadata['batch']).to eq(expected_config)
    end

    it 'deep merges metadata.batch and preserves omitted existing batch keys' do
      partial_runtime_config = {
        pretrained_checkpoint_url: 'staging-euclid-zoobot.ckpt',
        n_blocks: 3
      }

      patch(
        path,
        params: { metadata: { batch: partial_runtime_config } }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:ok)
      expect(json_parsed_response_body.dig('metadata', 'batch', 'pretrained_checkpoint_url')).to eq('staging-euclid-zoobot.ckpt')
      expect(json_parsed_response_body.dig('metadata', 'batch', 'n_blocks')).to eq(3)
      expect(json_parsed_response_body.dig('metadata', 'batch', 'training_script_path')).to eq('jwst/train_model_finetune_on_catalog.py')
      expect(context.reload.metadata.dig('batch', 'prediction_script_path')).to eq('jwst/predict_catalog_with_model.py')
      expect(context.metadata['fixed_crop']).to be_present
    end

    it 'accepts a relative pretrained checkpoint path' do
      runtime_config[:pretrained_checkpoint_url] = 'staging-euclid-zoobot.ckpt'

      patch(
        path,
        params: { metadata: { batch: runtime_config } }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:ok)
      expect(json_parsed_response_body.dig('metadata', 'batch', 'pretrained_checkpoint_url')).to eq('staging-euclid-zoobot.ckpt')
    end

    it 'rejects unsupported top-level patch keys' do
      patch(
        path,
        params: { unsupported_key: 'bad' }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_parsed_response_body['errors'].first['detail']).to include('at least one supported context field is required')
    end

    it 'rejects non-object JSON payloads' do
      patch(
        path,
        params: ['invalid'].to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_parsed_response_body['errors'].first['detail']).to include('at least one supported context field is required')
    end

    it 'rejects non-object metadata payloads' do
      patch(
        path,
        params: { metadata: 'invalid' }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_parsed_response_body['errors'].first['detail']).to include('metadata must be an object')
    end

    it 'rejects unknown module and extractor pairs' do
      patch(
        path,
        params: {
          module_name: 'new_project',
          extractor_name: 'missing'
        }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_parsed_response_body['errors'].first['detail']).to include('unknown module/extractor pair: new_project/missing')
    end

    it 'rejects an extractor update that does not match the existing module' do
      patch(
        path,
        params: {
          extractor_name: 'missing'
        }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_parsed_response_body['errors'].first['detail']).to include('unknown module/extractor pair: galaxy_zoo/missing')
    end

    it 'rejects non-integer context IDs' do
      patch(
        path,
        params: { workflow_id: 'not-an-integer' }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_parsed_response_body['errors'].first['detail']).to include('workflow_id must be an integer')
    end

    it 'rejects unknown batch runtime config keys' do
      patch(
        path,
        params: { metadata: { batch: runtime_config.merge(unknown_key: 'bad') } }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_parsed_response_body['errors'].first['detail']).to include('Unsupported batch runtime config keys')
    end

    it 'rejects unsafe script paths' do
      runtime_config[:training_script_path] = '../train.py'

      patch(
        path,
        params: { metadata: { batch: runtime_config } }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_parsed_response_body['errors'].first['detail']).to include('parent directory traversal')
    end

    it 'rejects unsupported checkpoint URL schemes' do
      runtime_config[:pretrained_checkpoint_url] = 'ftp://example.com/models/euclid.ckpt'

      patch(
        path,
        params: { metadata: { batch: runtime_config } }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_parsed_response_body['errors'].first['detail']).to include('HTTP(S) URL or relative checkpoint path')
    end

    it 'rejects non-object metadata batch payloads' do
      patch(
        path,
        params: { metadata: { batch: 'invalid' } }.to_json,
        headers: request_headers
      )

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_parsed_response_body['errors'].first['detail']).to include('metadata.batch must be an object')
    end

    context 'with invalid authentication credentials' do
      let(:request_headers) { json_headers_with_basic_auth('unknown', 'credentials') }

      it 'returns unauthorized response' do
        patch(
          path,
          params: { metadata: { batch: runtime_config } }.to_json,
          headers: request_headers
        )

        expect(response.status).to eq(401)
      end
    end
  end
end
