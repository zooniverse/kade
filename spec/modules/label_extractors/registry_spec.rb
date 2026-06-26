# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LabelExtractors::Registry do
  let(:config) do
    {
      'data_release_suffix' => 'np',
      'task_key_label_prefixes' => {
        'T0' => 'smooth-or-featured'
      },
      'task_key_data_labels' => {
        'T0' => {
          '0' => 'smooth'
        }
      }
    }
  end

  describe '.extractor_instance' do
    it 'resolves registered Galaxy Zoo code-backed extractors' do
      extractor = described_class.extractor_instance('galaxy_zoo', 'cosmic_dawn', 'T0')

      expect(extractor).to be_a(LabelExtractors::GalaxyZoo::CosmicDawn)
    end

    it 'falls back to enabled DB-backed extractor definitions' do
      LabelExtractorDefinition.create!(
        module_name: 'new_project',
        extractor_name: 'main',
        config: config
      )

      extractor = described_class.extractor_instance('new_project', 'main', 'T0')

      expect(extractor).to be_a(LabelExtractors::ConfigurableExtractor)
    end

    it 'prefers code-backed extractors over DB-backed definitions' do
      LabelExtractorDefinition.create!(
        module_name: 'galaxy_zoo',
        extractor_name: 'cosmic_dawn',
        config: config
      )

      extractor = described_class.extractor_instance('galaxy_zoo', 'cosmic_dawn', 'T0')

      expect(extractor).to be_a(LabelExtractors::GalaxyZoo::CosmicDawn)
    end

    it 'raises a clear error when no extractor exists' do
      expect {
        described_class.extractor_instance('unknown_project', 'main', 'T0')
      }.to raise_error(LabelExtractors::Finder::UnknownExtractor, "no extractor class found for 'unknown_project_main'")
    end
  end

  describe '.extractor_instance_from_lookup_key' do
    it 'resolves DB-backed extractors from lookup keys' do
      LabelExtractorDefinition.create!(
        module_name: 'new_project',
        extractor_name: 'main',
        config: config
      )

      extractor = described_class.extractor_instance_from_lookup_key('new_project_main_t0')

      expect(extractor.task_lookup_key).to eq('T0')
    end
  end

  describe '.label_column_headers' do
    it 'resolves DB-backed training CSV headers' do
      LabelExtractorDefinition.create!(
        module_name: 'new_project',
        extractor_name: 'main',
        config: config
      )

      expect(described_class.label_column_headers('new_project', 'main')).to eq(
        %w[id_str file_loc smooth-or-featured-np_smooth]
      )
    end
  end

  describe 'definition validation' do
    it 'accepts malformed DB-backed extractor config while strict schema validation is disabled' do
      definition = LabelExtractorDefinition.new(
        module_name: 'new_project',
        extractor_name: 'main',
        config: config.except('task_key_label_prefixes')
      )

      expect(definition).to be_valid
    end
  end
end
