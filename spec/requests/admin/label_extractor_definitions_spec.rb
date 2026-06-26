# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::LabelExtractorDefinitions', type: :request do
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

  it 'renders the global add definition page' do
    get '/admin/label_extractor_definitions/new', headers: request_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Add Label Extractor Definition')
    expect(response.body).to include('data-json-editor="true"')
  end

  it 'creates a new definition from the global admin page' do
    post '/admin/label_extractor_definitions',
      params: {
        label_extractor_definition: {
          module_name: context.module_name,
          extractor_name: context.extractor_name,
          enabled: '1',
          config_json: JSON.pretty_generate(
            data_release_suffix: 'jwst',
            task_key_label_prefixes: { T0: 'smooth-or-featured' },
            task_key_data_labels: { T0: { '0': 'smooth' } }
          )
        }
      },
      headers: request_headers

    expect(response).to redirect_to('/admin/label_extractor_definitions')

    definition = LabelExtractorDefinition.order(:id).last
    expect(definition.module_name).to eq(context.module_name)
    expect(definition.extractor_name).to eq(context.extractor_name)
  end

  it 're-renders the add page for invalid create input' do
    post '/admin/label_extractor_definitions',
      params: {
        label_extractor_definition: {
          module_name: context.module_name,
          extractor_name: context.extractor_name,
          enabled: '1',
          config_json: '{invalid-json'
        }
      },
      headers: request_headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('Add Label Extractor Definition')
    expect(response.body).to include(context.extractor_name)
    expect(response.body).to include('{invalid-json')
  end

  it 'renders the global definitions index' do
    LabelExtractorDefinition.create!(
      module_name: context.module_name,
      extractor_name: context.extractor_name,
      enabled: true,
      config: {
        data_release_suffix: 'jwst',
        task_key_label_prefixes: { T0: 'smooth-or-featured' },
        task_key_data_labels: { T0: { '0': 'smooth' } }
      }
    )

    get '/admin/label_extractor_definitions', headers: request_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Label Extractor Definitions')
    expect(response.body).to include(context.extractor_name)
  end

  it 'deletes a label extractor definition via the admin flow' do
    definition = LabelExtractorDefinition.create!(
      module_name: context.module_name,
      extractor_name: context.extractor_name,
      enabled: true,
      config: {
        data_release_suffix: 'jwst',
        task_key_label_prefixes: { T0: 'smooth-or-featured' },
        task_key_data_labels: { T0: { '0': 'smooth' } }
      }
    )

    delete "/admin/label_extractor_definitions/#{definition.id}", headers: request_headers

    expect(response).to redirect_to('/admin/label_extractor_definitions')
    expect(LabelExtractorDefinition.exists?(definition.id)).to be(false)
  end

  it 'redirects to the global definitions list after update from the list page' do
    definition = LabelExtractorDefinition.create!(
      module_name: context.module_name,
      extractor_name: context.extractor_name,
      enabled: true,
      config: {
        data_release_suffix: 'jwst',
        task_key_label_prefixes: { T0: 'smooth-or-featured' },
        task_key_data_labels: { T0: { '0': 'smooth' } }
      }
    )

    patch "/admin/label_extractor_definitions/#{definition.id}",
      params: {
        return_to: '/admin/label_extractor_definitions',
        label_extractor_definition: {
          module_name: definition.module_name,
          extractor_name: definition.extractor_name,
          enabled: '0',
          config_json: JSON.pretty_generate(definition.config)
        }
      },
      headers: request_headers

    expect(response).to redirect_to('/admin/label_extractor_definitions')
    expect(definition.reload.enabled).to be(false)
  end

  it 'redirects back to the context detail page after update from a context view' do
    definition = LabelExtractorDefinition.create!(
      module_name: context.module_name,
      extractor_name: context.extractor_name,
      enabled: true,
      config: {
        data_release_suffix: 'jwst',
        task_key_label_prefixes: { T0: 'smooth-or-featured' },
        task_key_data_labels: { T0: { '0': 'smooth' } }
      }
    )

    patch "/admin/label_extractor_definitions/#{definition.id}",
      params: {
        return_to: "/admin/contexts/#{context.id}",
        label_extractor_definition: {
          module_name: definition.module_name,
          extractor_name: definition.extractor_name,
          enabled: '0',
          config_json: JSON.pretty_generate(definition.config)
        }
      },
      headers: request_headers

    expect(response).to redirect_to("/admin/contexts/#{context.id}")
    expect(definition.reload.enabled).to be(false)
  end
end
