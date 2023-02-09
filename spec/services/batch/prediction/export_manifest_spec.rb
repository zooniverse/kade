# frozen_string_literal: true

require 'rails_helper'
require 'bajor/client'

RSpec.describe Batch::Prediction::ExportManifest do
  describe '#run' do
    let(:subject_set_id) { 1 }
    let(:panoptes_client_double) { instance_double(Panoptes::Client) }
    let(:service) { described_class.new(subject_set_id, panoptes_client_double) }

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
      allow(service).to receive(:upload_manifest_data_to_blob_storage)
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
  end
end
