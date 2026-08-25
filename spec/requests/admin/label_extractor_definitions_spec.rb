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
    expect(response.body).to include('Build custom schema')
    expect(response.body).to include('label_extractor_definition[build_custom_schema]')
    expect(response.body).to include('data-json-editor="true"')
  end

  it 'creates a new definition from the global admin page' do
    post '/admin/label_extractor_definitions',
      params: {
        label_extractor_definition: {
          module_name: context.module_name,
          extractor_name: context.extractor_name,
          enabled: '1',
          build_custom_schema: '1',
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
    expect(definition.config['build_custom_schema']).to be(true)
  end

  it 'sanitizes admin form input before saving' do
    post '/admin/label_extractor_definitions',
      params: {
        label_extractor_definition: {
          module_name: ' <b>new_project</b> ',
          extractor_name: ' <i>main</i> ',
          enabled: '1',
          build_custom_schema: '1',
          config_json: JSON.pretty_generate(
            '<b>task_key_label_prefixes</b>' => { '<b>T0</b>' => '<b>merger</b>' },
            '<b>task_key_data_labels</b>' => { '<b>T0</b>' => { '<b>0</b>' => '<b>yes</b>' } }
          )
        }
      },
      headers: request_headers

    expect(response).to redirect_to('/admin/label_extractor_definitions')

    definition = LabelExtractorDefinition.order(:id).last
    expect(definition.module_name).to eq('new_project')
    expect(definition.extractor_name).to eq('main')
    expect(definition.config).to include(
      'task_key_label_prefixes' => { 'T0' => 'merger' },
      'task_key_data_labels' => { 'T0' => { '0' => 'yes' } },
      'build_custom_schema' => true
    )
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

  it 'rejects unsafe custom schema values from the admin form' do
    post '/admin/label_extractor_definitions',
      params: {
        label_extractor_definition: {
          module_name: 'galaxy_zoo',
          extractor_name: 'gztt_local_1787071062',
          enabled: '1',
          build_custom_schema: '1',
          config_json: JSON.pretty_generate(
            task_key_label_prefixes: {
              T0: 'merger;echo bad'
            },
            task_key_data_labels: {
              T0: {
                '0': 'yes'
              }
            }
          )
        }
      },
      headers: request_headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('question merger;echo bad contains unsupported characters')
    expect(LabelExtractorDefinition.find_by(extractor_name: 'gztt_local_1787071062')).to be_nil
  end

  it 'rejects unsafe config values even when custom schema is disabled' do
    post '/admin/label_extractor_definitions',
      params: {
        label_extractor_definition: {
          module_name: 'galaxy_zoo',
          extractor_name: 'gztt_local_1787071063',
          enabled: '1',
          build_custom_schema: '0',
          config_json: JSON.pretty_generate(
            data_release_suffix: 'gztt',
            task_key_label_prefixes: {
              T0: 'merger;echo bad'
            },
            task_key_data_labels: {
              T0: {
                '0': 'yes'
              }
            }
          )
        }
      },
      headers: request_headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('question merger;echo bad contains unsupported characters')
    expect(LabelExtractorDefinition.find_by(extractor_name: 'gztt_local_1787071063')).to be_nil
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

  it 'clears the custom schema flag from the admin checkbox on update' do
    definition = LabelExtractorDefinition.create!(
      module_name: context.module_name,
      extractor_name: context.extractor_name,
      enabled: true,
      config: {
        build_custom_schema: true,
        data_release_suffix: 'gztt',
        task_key_label_prefixes: { T0: 'merger' },
        task_key_data_labels: { T0: { '0': 'yes' } }
      }
    )

    patch "/admin/label_extractor_definitions/#{definition.id}",
      params: {
        return_to: '/admin/label_extractor_definitions',
        label_extractor_definition: {
          module_name: definition.module_name,
          extractor_name: definition.extractor_name,
          enabled: '1',
          build_custom_schema: '0',
          config_json: JSON.pretty_generate(definition.config)
        }
      },
      headers: request_headers

    expect(response).to redirect_to('/admin/label_extractor_definitions')
    expect(definition.reload.config).not_to have_key('build_custom_schema')
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
