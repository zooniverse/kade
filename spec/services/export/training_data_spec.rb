# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Export::TrainingData do
  describe '#run' do
    let(:workflow_id) { 123 }
    let(:file_time) { Time.now.iso8601 }
    let(:storage_path) { "#{Zoobot::Storage.path_key(workflow_id)}-#{file_time}.csv" }
    let(:storage_path_file_name) { "workflow-#{workflow_id}-#{file_time}.csv" }
    let(:storage_path_key) { "/catalogues/test/#{storage_path_file_name}" }

    let(:training_data_model) { TrainingDataExport.new(workflow_id: workflow_id, storage_path: storage_path) }
    let(:export_service_instance) { described_class.new(training_data_model) }
    let(:formatter_double) { instance_double(Format::TrainingDataCsv) }

    let(:temp_export_file) { Tempfile.new }
    let(:active_storage_proxy) { training_data_model.file }

    before do
      allow(TrainingDataExport).to receive(:create).and_return(training_data_model)
      allow(formatter_double).to receive(:run).and_return(temp_export_file)
      allow(Format::TrainingDataCsv).to receive(:new).and_return(formatter_double)
      allow(active_storage_proxy).to receive(:attach)
      allow(active_storage_proxy).to receive(:attached?).and_return(true)
    end

    it 'does not raise unexpected errors' do
      expect { export_service_instance.run }.not_to raise_error
    end

    it 'calls the formatter service' do
      export_service_instance.run
      expect(formatter_double).to have_received(:run).once
    end

    it 'uploads the export file at a known storage key' do
      attach_params = { key: storage_path_key, io: temp_export_file, filename: storage_path_file_name }
      export_service_instance.run
      expect(active_storage_proxy).to have_received(:attach).with(attach_params)
    end

    it 'marks the export model as finished' do
      expect { export_service_instance.run }.to change(training_data_model, :finished?).from(false).to(true)
    end

    it 'records the storage path on the export model' do
      export_service_instance.run
      expect(training_data_model.storage_path).to match(storage_path)
    end

    context 'with an failed remote file upload' do
      before do
        allow(active_storage_proxy).to receive(:attached?).and_return(false)
      end

      it 'marks the export model as failed!' do
        export_service_instance.run
        expect(training_data_model.failed?).to be(true)
      end
    end

    context 'with a DB-backed label extractor definition' do
      let(:workflow_id) { 556 }

      before do
        Context.create!(
          workflow_id: workflow_id,
          project_id: 43,
          active_subject_set_id: 601,
          pool_subject_set_id: 602,
          module_name: 'new_project',
          extractor_name: 'main'
        )
        LabelExtractorDefinition.create!(
          module_name: 'new_project',
          extractor_name: 'main',
          config: {
            data_release_suffix: 'np',
            task_key_label_prefixes: { T0: 'smooth-or-featured' },
            task_key_data_labels: { T0: { '0': 'smooth' } }
          }
        )
      end

      it 'uses registry-backed label headers' do
        export_service_instance.run

        expect(Format::TrainingDataCsv).to have_received(:new).with(
          workflow_id,
          %w[id_str file_loc smooth-or-featured-np_smooth]
        )
      end
    end
  end
end
