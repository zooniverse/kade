# frozen_string_literal: true

require 'rails_helper'
require 'panoptes/api'

RSpec.describe 'Azure candidate pool POC' do
  let(:context) do
    Context.create!(project_id: 1, workflow_id: 2, active_subject_set_id: 3,
                    prediction_source: 'azure_catalogue', module_name: 'galaxy_zoo', extractor_name: 'cosmic_dawn',
                    metadata: {
                      selection: { randomisation_factor: 0 },
                      batch: { prediction_script_path: 'predict_catalog_with_model.py',
                               pretrained_checkpoint_url: 'https://example.com/models/poc.ckpt' }
                    })
  end
  let(:container) { Zoobot::Storage.container_name }
  let(:prefix) { "catalogues/#{Rails.env}/images/" }
  let(:external_id) { "#{container}/#{prefix}a.jpg" }
  let(:locations) { [{ 'image/jpeg' => "https://pocstorage.blob.core.windows.net/#{external_id}" }] }
  let(:uploaded_rows) { [] }
  let(:current_ids) { [] }
  let(:panoptes_url) { 'https://panoptes-staging.zooniverse.org/api' }

  before do
    blob_client = Azure::Storage::Blob::BlobService.create(
      storage_account_name: 'pocstorage', storage_access_key: Base64.strict_encode64('test-key')
    )
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('AZURE_STORAGE_ACCOUNT_NAME').and_return('pocstorage')
    allow(ENV).to receive(:fetch).with('AZURE_STORAGE_ACCESS_KEY').and_return(Base64.strict_encode64('test-key'))
    allow(Azure::Storage::Blob::BlobService).to receive(:create).and_return(blob_client)
    blobs = %w[a.jpg never-selected.jpg].map do |filename|
      "<Blob><Name>#{prefix}#{filename}</Name><Properties>" \
        '<Last-Modified>Wed, 21 Oct 2026 00:00:00 GMT</Last-Modified><Etag>0x1</Etag>' \
        '<Content-Length>10</Content-Length><Content-Type>image/jpeg</Content-Type>' \
        '<BlobType>BlockBlob</BlobType></Properties></Blob>'
    end.join
    stub_request(:get, "https://pocstorage.blob.core.windows.net/#{container}")
      .with(query: { comp: 'list', restype: 'container', prefix: prefix })
      .to_return(headers: { 'Content-Type' => 'application/xml' },
                 body: "<EnumerationResults><Blobs>#{blobs}</Blobs><NextMarker></NextMarker></EnumerationResults>")
    allow(ActiveStorage::Blob).to receive(:create_and_upload!) do |**attributes|
      uploaded_rows.replace(JSON.parse(attributes.fetch(:io).read))
      ActiveStorage::Blob.new(key: attributes.fetch(:key))
    end
    allow(PredictionJobSubmissionJob).to receive(:perform_async).and_return('queued')
    allow(PredictionJobMonitorJob).to receive(:perform_in).and_return('monitor-queued')
    allow(ProcessPredictionResultsJob).to receive(:perform_async).and_return('results-queued')
    allow(Panoptes::Api).to receive(:client).and_return(Panoptes::Client.new(env: :staging))
    stub_request(:get, "#{panoptes_url}/subject_sets/3").to_return(
      headers: { 'Content-Type' => 'application/json' },
      body: { subject_sets: [{ id: '3', links: { project: '1' } }] }.to_json
    )
    stub_request(:get, "#{panoptes_url}/subjects").with(query: { subject_set_id: '3' }).to_return do
      { headers: { 'Content-Type' => 'application/json' }, body: {
        subjects: current_ids.map { |id| { id: id } }, meta: { subjects: { next_href: nil } }
      }.to_json }
    end
  end

  def complete_predictions(score)
    expect { PredictionManifestExportJob.new.perform(context.id) }.not_to change(CandidateSubject, :count)
    job = PredictionJob.order(:id).last
    stub_request(:get, job.manifest_url).to_return(body: uploaded_rows.to_json)
    service_id = "candidate-poc-#{job.id}"
    submission = stub_request(:post, "#{Bajor::Client.base_uri}/prediction/jobs/").with do |request|
      payload = JSON.parse(request.body)
      payload.fetch('manifest_url') == job.manifest_url && payload.fetch('opts') == {
        'workflow_name' => 'cosmic_dawn', 'prediction_script_path' => 'predict_catalog_with_model.py',
        'pretrained_checkpoint_url' => 'https://example.com/models/poc.ckpt'
      }
    end.to_return(status: 201, headers: { 'Content-Type' => 'application/json' }, body: { id: service_id }.to_json)
    status = {
      tasks: [{ execution_info: { result: nil } }],
      common_environment_settings: [{ name: 'PREDICTIONS_JOB_RESULTS_DIR', value: "jobs/#{service_id}/results" }]
    }
    completed_status = status.deep_merge(tasks: [{ execution_info: { result: 'success' } }])
    monitor = stub_request(:get, "#{Bajor::Client.base_uri}/prediction/job/#{service_id}")
              .to_return(headers: { 'Content-Type' => 'application/json' }, body: status.to_json)
              .then.to_return(headers: { 'Content-Type' => 'application/json' }, body: completed_status.to_json)

    expect { PredictionJobSubmissionJob.new.perform(job.id) }.not_to change(CandidateSubject, :count)
    expect(job.reload.state).to eq('submitted')
    PredictionJobMonitorJob.new.perform(job.id)
    expect(job.reload.state).to eq('submitted')
    expect(ProcessPredictionResultsJob).not_to have_received(:perform_async).with(job.id)
    expect(PredictionJobMonitorJob).to have_received(:perform_in)
      .with(PredictionJobMonitorJob::MONITOR_JOB_RESCHEDULE_DELAY.minute, job.id)

    results = uploaded_rows.to_h do |row|
      id = JSON.parse(row.last).fetch('subject_id')
      [id, { '0' => [id == external_id ? score : 0.1] }]
    end
    results_url = "#{Bajor::Client::BLOB_STORE_HOST_CONTAINER_URL}/predictions/jobs/#{service_id}/results/predictions.json"
    stub_request(:get, results_url).to_return(body: { data: results }.to_json)
    PredictionJobMonitorJob.new.perform(job.id)
    expect(job.reload.state).to eq('completed')
    expect(job.results_url).to eq(results_url)
    expect(ProcessPredictionResultsJob).to have_received(:perform_async).with(job.id).once
    ProcessPredictionResultsJob.new.perform(job.id)
    expect(submission).to have_been_requested.once
    expect(monitor).to have_been_requested.twice
    job.reload
  end

  it 'discovers, predicts, saves only selected images, and reuses the mapping through deselection and reselection' do
    creation = stub_request(:post, "#{panoptes_url}/subjects").with do |request|
      payload = JSON.parse(request.body).fetch('subjects')
      payload.fetch('locations') == locations && payload.dig('links', 'project') == 1
    end.to_return(headers: { 'Content-Type' => 'application/json' }, body: { subjects: [{ id: '101' }] }.to_json)
    addition = stub_request(:post, "#{panoptes_url}/subject_sets/3/links/subjects")
               .with(body: { subjects: ['101'] }.to_json).to_return(body: '{}')
    removal = stub_request(:delete, "#{panoptes_url}/subject_sets/3/links/subjects/101").to_return(body: '{}')

    first = complete_predictions(0.9)
    expect(uploaded_rows.size).to eq(2)
    expect(JSON.parse(uploaded_rows.first.last)['subject_id']).to eq(external_id)
    expect(first.context_id).to eq(context.id)
    expect(first.catalogue_snapshot).to eq(
      'project_id' => 1, 'selection' => { 'probability_threshold' => 0.8, 'randomisation_factor' => 0 }
    )
    expect(first.applied_at).to be_present
    expect(CandidateSubject.sole.external_id).to eq(external_id)
    expect(CandidateSubject.sole.zooniverse_subject_id).to eq(101)

    current_ids << '101'
    second = complete_predictions(0.1)
    expect(second.selection['selected']).to be_empty
    expect(removal).to have_been_requested.once
    expect(CandidateSubject.count).to eq(1)

    current_ids.clear
    complete_predictions(0.9)
    expect(creation).to have_been_requested.once
    expect(addition).to have_been_requested.twice
    expect(CandidateSubject.count).to eq(1)
  end
end
