# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin::Contexts', type: :request do
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

  it 'renders the admin contexts index' do
    get '/admin/contexts', headers: request_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Contexts')
    expect(response.body).to include(context.extractor_name)
  end

  it 'shows enabled, disabled, and none definition states on the index' do
    enabled_context = Context.create!(
      workflow_id: 9001,
      project_id: 1001,
      active_subject_set_id: 1101,
      pool_subject_set_id: 1201,
      module_name: 'new_project',
      extractor_name: 'enabled_definition',
      metadata: {}
    )
    disabled_context = Context.create!(
      workflow_id: 9002,
      project_id: 1002,
      active_subject_set_id: 1102,
      pool_subject_set_id: 1202,
      module_name: 'new_project',
      extractor_name: 'disabled_definition',
      metadata: {}
    )
    none_context = Context.create!(
      workflow_id: 9003,
      project_id: 1003,
      active_subject_set_id: 1103,
      pool_subject_set_id: 1203,
      module_name: 'new_project',
      extractor_name: 'no_definition',
      metadata: {}
    )

    LabelExtractorDefinition.create!(
      module_name: enabled_context.module_name,
      extractor_name: enabled_context.extractor_name,
      enabled: true,
      config: {
        data_release_suffix: 'np',
        task_key_label_prefixes: { T0: 'smooth-or-featured' },
        task_key_data_labels: { T0: { '0': 'smooth' } }
      }
    )
    LabelExtractorDefinition.create!(
      module_name: disabled_context.module_name,
      extractor_name: disabled_context.extractor_name,
      enabled: false,
      config: {
        data_release_suffix: 'np',
        task_key_label_prefixes: { T0: 'smooth-or-featured' },
        task_key_data_labels: { T0: { '0': 'smooth' } }
      }
    )

    get '/admin/contexts', headers: request_headers

    expect(response.body).to include('Enabled')
    expect(response.body).to include('Disabled')
    expect(response.body).to include('None')
  end

  it 'renders the add context page' do
    get '/admin/contexts/new', headers: request_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Add Context')
    expect(response.body).to include('data-json-editor="true"')
  end

  it 'renders the admin context detail page' do
    get "/admin/contexts/#{context.id}", headers: request_headers

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Context #{context.id}")
    expect(response.body).to include(context.module_name)
  end

  it 'updates a context via the admin form flow' do
    patch "/admin/contexts/#{context.id}",
      params: {
        context: {
          workflow_id: 1234,
          project_id: context.project_id,
          active_subject_set_id: context.active_subject_set_id,
          pool_subject_set_id: context.pool_subject_set_id,
          module_name: context.module_name,
          extractor_name: context.extractor_name,
          metadata_json: JSON.pretty_generate(context.metadata)
        }
      },
      headers: request_headers

    expect(response).to redirect_to("/admin/contexts/#{context.id}")
    expect(context.reload.workflow_id).to eq(1234)
  end

  it 'creates a context via the admin form flow' do
    LabelExtractorDefinition.create!(
      module_name: 'new_project',
      extractor_name: 'main',
      enabled: true,
      config: {
        data_release_suffix: 'np',
        task_key_label_prefixes: { T0: 'smooth-or-featured' },
        task_key_data_labels: { T0: { '0': 'smooth' } }
      }
    )

    expect {
      post '/admin/contexts',
        params: {
          context: {
            workflow_id: 9991,
            project_id: 555,
            active_subject_set_id: 666,
            pool_subject_set_id: 777,
            module_name: 'new_project',
            extractor_name: 'main',
            metadata_json: JSON.pretty_generate(batch: { pretrained_checkpoint_url: 'rubin.ckpt' })
          }
        },
        headers: request_headers
    }.to change(Context, :count).by(1)

    created = Context.order(:id).last
    expect(response).to redirect_to("/admin/contexts/#{created.id}")
    expect(created.module_name).to eq('new_project')
    expect(created.metadata.dig('batch', 'pretrained_checkpoint_url')).to eq('rubin.ckpt')
  end

  it 'deletes a context via the admin flow' do
    delete "/admin/contexts/#{context.id}", headers: request_headers

    expect(response).to redirect_to('/admin/contexts')
    expect(Context.exists?(context.id)).to be(false)
  end

  context 'with invalid credentials' do
    let(:request_headers) do
      {
        'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials('unknown', 'credentials')
      }
    end

    it 'returns unauthorized' do
      get '/admin/contexts', headers: request_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
