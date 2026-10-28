# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidatePool::SyncAzure do
  let(:context) do
    Context.create!(project_id: 1, workflow_id: 2, active_subject_set_id: 3,
                    prediction_source: 'azure_catalogue')
  end
  let(:client) do
    Azure::Storage::Blob::BlobService.create(
      storage_account_name: 'pocstorage', storage_access_key: Base64.strict_encode64('test-key')
    )
  end
  let(:service) { described_class.new(context, blob_client: client) }
  let(:container) { Zoobot::Storage.container_name }
  let(:prefix) { "catalogues/#{Rails.env}/images/" }
  let(:url) { "https://pocstorage.blob.core.windows.net/#{container}" }
  let(:query) { { comp: 'list', restype: 'container', prefix: prefix } }

  def page_xml(names, marker = '')
    blobs = names.map do |name|
      "<Blob><Name>#{CGI.escapeHTML(name)}</Name><Properties>" \
        '<Last-Modified>Wed, 21 Oct 2026 00:00:00 GMT</Last-Modified>' \
        '<Etag>0x1</Etag><Content-Length>10</Content-Length>' \
        '<Content-Type>application/octet-stream</Content-Type><BlobType>BlockBlob</BlobType>' \
        '</Properties></Blob>'
    end.join
    "<EnumerationResults><Blobs>#{blobs}</Blobs><NextMarker>#{marker}</NextMarker></EnumerationResults>"
  end

  def stub_page(names, marker: nil, next_marker: '')
    page_query = marker ? query.merge(marker: marker) : query
    stub_request(:get, url).with(query: page_query).to_return(
      headers: { 'Content-Type' => 'application/xml' }, body: page_xml(names, next_marker)
    )
  end

  it 'lists every page and returns one image per blob without saving database records' do
    first = stub_page(["#{prefix}first/a.jpg", "#{prefix}readme.txt"], next_marker: 'page-2')
    second = stub_page(["#{prefix}second/a.png"], marker: 'page-2')

    rows = nil
    expect { rows = service.run }.not_to change(CandidateSubject, :count)
    expect(rows.map { |row| row.fetch('external_id') }).to eq([
      "#{container}/#{prefix}first/a.jpg", "#{container}/#{prefix}second/a.png"
    ])
    expect(rows.first.fetch('metadata')).to eq('!filename' => 'a.jpg')
    expect(rows.first.fetch('locations')).to eq([{ 'image/jpeg' => "#{url}/#{prefix}first/a.jpg" }])
    expect(first).to have_been_requested.once
    expect(second).to have_been_requested.once
  end

  it 'returns the same identities on repeat scans without saving records' do
    stub_page(["#{prefix}a.jpg"])
    original = service.run
    expect(service.run).to eq(original)
    expect(context.candidate_subjects).to be_empty
  end

  it 'encodes special characters in URLs and recognises uppercase image extensions' do
    stub_page(["#{prefix}a & b.PNG"])
    expect(service.run.sole.fetch('locations')).to eq([
      { 'image/png' => "#{url}/#{prefix}a%20%26%20b.PNG" }
    ])
  end

  it 'returns an empty catalogue for non-image files without deleting existing mappings' do
    existing = context.candidate_subjects.create!(external_id: 'previous', zooniverse_subject_id: 101,
                                                 locations: [{ 'image/jpeg' => 'https://example.com/a.jpg' }])
    stub_page(["#{prefix}readme.txt", "#{prefix}movie.mp4"])
    expect(service.run).to eq([])
    expect(context.candidate_subjects.reload.map(&:id)).to eq([existing.id])
  end

  it 'fails without database writes when a later listing page fails' do
    stub_page(["#{prefix}a.jpg"], next_marker: 'page-2')
    stub_request(:get, url).with(query: query.merge(marker: 'page-2')).to_return(status: 403)
    expect { service.run }.to raise_error(Azure::Core::Http::HTTPError)
    expect(context.candidate_subjects).to be_empty
  end

  it 'uses the container configured by Zoobot storage' do
    stub_const('Zoobot::Storage::CONTAINER_NAME', 'custom-images')
    stub_page(["#{prefix}a.jpg"])
    row = service.run.sole
    expect(row.fetch('external_id')).to eq("custom-images/#{prefix}a.jpg")
    expect(row.fetch('locations')).to eq([
      { 'image/jpeg' => "https://pocstorage.blob.core.windows.net/custom-images/#{prefix}a.jpg" }
    ])
  end

  it 'rejects Panoptes pool mode before contacting Azure' do
    context.update!(prediction_source: 'panoptes_subject_set', pool_subject_set_id: 4)
    expect { service.run }.to raise_error(ArgumentError, /azure_catalogue/)
  end
end
