# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LabelExtractors::ConfigurableExtractor do
  let(:config) do
    {
      'data_release_suffix' => 'np',
      'task_key_label_prefixes' => {
        'T0' => 'smooth-or-featured'
      },
      'task_key_data_labels' => {
        'T0' => {
          '0' => 'smooth',
          '1' => 'featured',
          '2' => 'artifact'
        }
      }
    }
  end

  describe '#extract' do
    it 'extracts labels using structured config' do
      extractor = described_class.new('T0', config)

      expect(extractor.extract('0' => 4, '1' => 2)).to eq(
        'smooth-or-featured-np_smooth' => 4,
        'smooth-or-featured-np_featured' => 2
      )
    end

    it 'raises for unknown task keys' do
      expect {
        described_class.new('T99', config)
      }.to raise_error(LabelExtractors::UnknownTaskKey, 'key not found: T99')
    end

    it 'raises for unknown answer keys' do
      extractor = described_class.new('T0', config)

      expect {
        extractor.extract('99' => 1)
      }.to raise_error(LabelExtractors::UnknownLabelKey, 'key not found: 99')
    end

    it 'raises a clear error for malformed config' do
      malformed_config = config.except('task_key_data_labels')

      expect {
        described_class.new('T0', malformed_config)
      }.to raise_error(LabelExtractors::ConfigurationError, 'task_key_data_labels must be a non-empty object')
    end
  end

  describe '.question_answers_schema' do
    it 'generates training data headers from config' do
      expect(described_class.question_answers_schema(config)).to eq(
        %w[
          smooth-or-featured-np_smooth
          smooth-or-featured-np_featured
          smooth-or-featured-np_artifact
        ]
      )
    end
  end
end
