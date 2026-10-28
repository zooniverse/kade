# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidatePool::ExportManifest do
  let(:context) do
    Context.create!(project_id: 1, workflow_id: 2, active_subject_set_id: 3,
                    prediction_source: 'azure_catalogue', metadata: {
                      selection: { probability_threshold: 0.6 }
                    })
  end
  let(:candidates) do
    [{ 'external_id' => 'training/catalogues/test/images/a.jpg', 'metadata' => { '!filename' => 'a.jpg' },
       'locations' => [{ 'image/jpeg' => 'https://example.com/a.jpg' }] }]
  end
  let(:uploaded) { [] }
  let(:sync) { instance_double(CandidatePool::SyncAzure, run: candidates) }

  before do
    allow(CandidatePool::SyncAzure).to receive(:new).with(context).and_return(sync)
    allow(ActiveStorage::Blob).to receive(:create_and_upload!) do |**attributes|
      uploaded << JSON.parse(attributes.fetch(:io).read)
      ActiveStorage::Blob.new(key: attributes.fetch(:key))
    end
  end

  it 'exports image identities and metadata without saving candidate records or IDs in the job snapshot' do
    service = nil
    expect { service = described_class.new(context).run }.not_to change(CandidateSubject, :count)
    url, metadata_json = uploaded.sole.sole
    expect(url).to eq('https://example.com/a.jpg')
    expect(JSON.parse(metadata_json)).to eq(
      'project_id' => 1, 'subject_id' => candidates.sole.fetch('external_id'),
      'mime_type' => 'image/jpeg', 'metadata' => { '!filename' => 'a.jpg' }
    )
    expect(service.manifest_url).to include('/predictions/catalogues/test/candidates-')
    expect(service.snapshot).to eq(
      'project_id' => 1,
      'selection' => { 'probability_threshold' => 0.6, 'randomisation_factor' => 0.2 }
    )
    expect(ActiveStorage::Blob).to have_received(:create_and_upload!).with(hash_including(service_name: 'test-predictions'))
  end

  it 'captures a fixed manifest and settings independently of later changes' do
    service = described_class.new(context).run
    context.update!(metadata: { selection: { probability_threshold: 0.9 } })
    candidates.sole['metadata']['!filename'] = 'changed.jpg'
    expect(JSON.parse(uploaded.sole.sole.last).fetch('metadata')).to eq('!filename' => 'a.jpg')
    expect(service.snapshot['selection']['probability_threshold']).to eq(0.6)
  end

  it 'does not use old database catalogue records as prediction inputs' do
    context.candidate_subjects.create!(external_id: 'old', locations: [{ 'image/png' => 'https://example.com/old.png' }])
    described_class.new(context).run
    expect(uploaded.sole.map(&:first)).to eq(['https://example.com/a.jpg'])
  end

  it 'rejects an empty Azure listing before uploading anything' do
    candidates.clear
    expect { described_class.new(context).run }.to raise_error(ArgumentError, /empty/)
    expect(ActiveStorage::Blob).not_to have_received(:create_and_upload!)
  end

  it 'does not upload a partial catalogue if discovery fails' do
    allow(sync).to receive(:run).and_raise(StandardError, 'Azure unavailable')
    expect { described_class.new(context).run }.to raise_error(StandardError, 'Azure unavailable')
    expect(ActiveStorage::Blob).not_to have_received(:create_and_upload!)
  end
end
