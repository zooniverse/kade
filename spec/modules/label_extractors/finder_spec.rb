# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LabelExtractors::Finder do
  let(:task_schema_lookup_key) { 'galaxy_zoo_cosmic_dawn_t0' }

  describe '.extractor_instance' do
    it 'returns the correct label extractor type' do
      label_extractor = described_class.extractor_instance(task_schema_lookup_key)
      expect(label_extractor).to be_a(LabelExtractors::GalaxyZoo::CosmicDawn)
    end

    it 'raises an error if the extractor class is unknown' do
      expect {
        described_class.extractor_instance('unknown_project_decals_t0')
      }.to raise_error(LabelExtractors::Finder::UnknownExtractor, "no extractor class found for 'unknown_project_decals_t0'")
    end

    it 'correctly sets the task_lookup_key' do
      label_extractor = described_class.extractor_instance(task_schema_lookup_key)
      expect(label_extractor.task_lookup_key).to eq('T0')
    end

    it 'raises an error if the task key is not known for the label schema' do
      expect {
        described_class.extractor_instance('galaxy_zoo_cosmic_dawn_t50')
      }.to raise_error(LabelExtractors::GalaxyZoo::UnknownTaskKey, 'key not found: T50')
    end

    it 'finds the decals mission data' do
      label_extractor = described_class.extractor_instance('galaxy_zoo_decals_t0')
      expect(label_extractor.task_lookup_key).to eq('T0')
    end

    it 'finds DB-backed extractor definitions' do
      LabelExtractorDefinition.create!(
        module_name: 'new_project',
        extractor_name: 'main',
        config: {
          data_release_suffix: 'np',
          task_key_label_prefixes: { T0: 'smooth-or-featured' },
          task_key_data_labels: { T0: { '0': 'smooth' } }
        }
      )

      label_extractor = described_class.extractor_instance('new_project_main_t0')

      expect(label_extractor).to be_a(LabelExtractors::ConfigurableExtractor)
      expect(label_extractor.task_lookup_key).to eq('T0')
    end
  end
end
