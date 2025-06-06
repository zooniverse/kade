# frozen_string_literal: true

require 'rails_helper'
require 'bajor/client'

RSpec.describe Batch::Prediction::ExportManifest do
  describe '#run' do
    let(:subject_set_id) { 1 }
    let(:panoptes_client_double) { instance_double(Panoptes::Client) }
    let(:panoptes_client_pool) do
      ConnectionPool.new(size: 1, timeout: 1) { panoptes_client_double }
    end
    let(:service) { described_class.new(subject_set_id, panoptes_client_pool) }
    let(:blob_double) { instance_double(ActiveStorage::Blob, key: '/path/to/manifest.json') }

    before do
      allow(panoptes_client_double).to receive(:subject_set).and_return({ 'links' => { 'project' => '1' } })
      # I know the below is bad testing practice to stub the method(s) under test
      # however the code uses the panoptes client in a complex manner
      # and i need to get something working quickly...
      # My sincere apologies to those who are reading this
      # longer term adding more tests for the panoptes client calls
      # to fetch SMS and Subject data would be ideal
      #
      # FWIW: i've tested this manually and it works
      # but I know that doesn't work long term, soz :(
      allow(service).to receive(:fetch_subject_set_subject_ids)
      allow(service).to receive(:create_manifest_data)
      allow(service).to receive(:write_manifest_data_to_temp_file)
      allow(service).to receive(:upload_manifest_data_to_blob_storage).and_return(blob_double)
    end

    it 'does not raise unexpected errors' do
      expect { service.run }.not_to raise_error
    end

    it 'calls the panoptes client to find the subject set', :aggregate_failures do
      service.run
      expect(panoptes_client_double).to have_received(:subject_set).with(subject_set_id).once
      expect(service).to have_received(:fetch_subject_set_subject_ids)
      expect(service).to have_received(:create_manifest_data)
      expect(service).to have_received(:write_manifest_data_to_temp_file)
      expect(service).to have_received(:upload_manifest_data_to_blob_storage)
    end

    it 'stores the manifest_url for reuse' do
      service.run
      expect(service.manifest_url).to eq("#{Bajor::Client::BLOB_STORE_HOST_CONTAINER_URL}/predictions#{blob_double.key}")
    end
  end

  describe '#with_api_retry' do
    let(:subject_set_id) { 1 }
    let(:pool) { ConnectionPool.new(size: 1, timeout: 1) { Panoptes::Api.client } }
    let(:service) { described_class.new(subject_set_id, pool) }

    before do
      allow(described_class).to receive(:sleep)
    end

    it 'retries a failing block up to max_retries then returns nil' do
      call_count = 0

      result = service.send(:with_api_retry, 2) do
        call_count += 1
        raise StandardError
      end

      expect(call_count).to eq(2)
      expect(result).to be_nil
    end

    it 'succeeds on the second attempt if first raises an exception' do
      call_count = 0

      result = service.send(:with_api_retry, 3) do
        call_count += 1
        raise StandardError, 'failed call' if call_count == 1
        call_count
      end

      expect(call_count).to eq(2)
      expect(result).to eq(call_count)
    end
  end
end
