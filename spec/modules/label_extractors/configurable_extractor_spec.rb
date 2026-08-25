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

    it 'ignores the data release suffix when building a custom schema' do
      extractor = described_class.new('T0', config.merge('build_custom_schema' => true))

      expect(extractor.extract('0' => 4, '1' => 2)).to eq(
        'smooth-or-featured_smooth' => 4,
        'smooth-or-featured_featured' => 2
      )
    end

    it 'does not require a data release suffix when building a custom schema' do
      extractor = described_class.new('T0', config.except('data_release_suffix').merge('build_custom_schema' => true))

      expect(extractor.extract('0' => 4)).to eq(
        'smooth-or-featured_smooth' => 4
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

    it 'raises a configuration error when required mappings are missing' do
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

    it 'generates training data headers without the data release suffix for custom schemas' do
      expect(described_class.question_answers_schema(config.merge('build_custom_schema' => true))).to eq(
        %w[
          smooth-or-featured_smooth
          smooth-or-featured_featured
          smooth-or-featured_artifact
        ]
      )
    end
  end

  describe '.custom_schema' do
    it 'returns nil when custom schema building is disabled' do
      expect(described_class.custom_schema(config)).to be_nil
    end

    it 'rejects unsafe question names even when custom schema building is disabled' do
      unsafe_config = config.merge(
        'task_key_label_prefixes' => {
          'T0' => 'merger;echo bad'
        }
      )

      expect {
        described_class.question_answers_schema(unsafe_config)
      }.to raise_error(LabelExtractors::ConfigurationError, /question merger;echo bad contains unsupported characters/)
    end

    it 'rejects unsafe data release suffixes' do
      unsafe_config = config.merge('data_release_suffix' => 'np;echo bad')

      expect {
        described_class.question_answers_schema(unsafe_config)
      }.to raise_error(LabelExtractors::ConfigurationError, /data_release_suffix np;echo bad contains unsupported characters/)
    end

    it 'builds a no-dependency Zoobot schema from the extractor config' do
      custom_schema_config = {
        'build_custom_schema' => true,
        'task_key_label_prefixes' => {
          'T0' => 'merger'
        },
        'task_key_data_labels' => {
          'T0' => {
            '0' => 'yes',
            '1' => 'no',
            '2' => 'artifact'
          }
        }
      }

      expect(described_class.custom_schema(custom_schema_config)).to eq(
        'question_answer_pairs' => {
          'merger' => %w[_yes _no _artifact]
        },
        'dependencies' => {
          'merger' => nil
        }
      )
    end

    it 'preserves configured dependencies by question name' do
      dependent_config = config.merge(
        'build_custom_schema' => true,
        'dependencies' => {
          'smooth-or-featured' => nil,
          'bar' => 'smooth-or-featured_featured'
        },
        'task_key_label_prefixes' => config['task_key_label_prefixes'].merge('T1' => 'bar'),
        'task_key_data_labels' => config['task_key_data_labels'].merge('T1' => { '0' => 'baz' })
      )

      expect(described_class.custom_schema(dependent_config)).to eq(
        'question_answer_pairs' => {
          'smooth-or-featured' => %w[_smooth _featured _artifact],
          'bar' => %w[_baz]
        },
        'dependencies' => {
          'smooth-or-featured' => nil,
          'bar' => 'smooth-or-featured_featured'
        }
      )
    end

    it 'allows configured dependencies to use task keys' do
      dependent_config = config.merge(
        'build_custom_schema' => true,
        'dependencies' => {
          'T0' => nil
        }
      )

      expect(described_class.custom_schema(dependent_config)).to include(
        'dependencies' => {
          'smooth-or-featured' => nil
        }
      )
    end

    it 'rejects unsafe question names' do
      unsafe_config = config.merge(
        'build_custom_schema' => true,
        'task_key_label_prefixes' => {
          'T0' => 'merger;echo bad'
        }
      )

      expect {
        described_class.custom_schema(unsafe_config)
      }.to raise_error(LabelExtractors::ConfigurationError, /question merger;echo bad contains unsupported characters/)
    end

    it 'rejects unsafe answer names' do
      unsafe_config = config.merge(
        'build_custom_schema' => true,
        'task_key_data_labels' => {
          'T0' => {
            '0' => 'yes;echo bad'
          }
        }
      )

      expect {
        described_class.custom_schema(unsafe_config)
      }.to raise_error(LabelExtractors::ConfigurationError, /answer _yes;echo bad contains unsupported characters/)
    end

    it 'rejects dependencies that do not point to generated schema labels' do
      unsafe_config = config.merge(
        'build_custom_schema' => true,
        'dependencies' => {
          'smooth-or-featured' => 'missing_answer'
        }
      )

      expect {
        described_class.custom_schema(unsafe_config)
      }.to raise_error(LabelExtractors::ConfigurationError, /dependency missing_answer must reference a generated schema label/)
    end
  end
end
