# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Batch::ContextRuntimeOptions do
  fixtures :contexts

  let(:context) { contexts(:galaxy_zoo_cosmos_active_learning_project) }
  context 'when a DB-backed extractor builds the custom schema' do
    let(:context) do
      Context.create!(
        workflow_id: 998,
        project_id: 41,
        active_subject_set_id: 997,
        pool_subject_set_id: 996,
        module_name: 'galaxy_zoo',
        extractor_name: 'gztt',
        metadata: { 'batch' => {} }
      )
    end

    let(:generated_custom_schema) do
      {
        'question_answer_pairs' => {
          'merger' => %w[_yes _no _artifact]
        },
        'dependencies' => {
          'merger' => nil
        }
      }
    end

    before do
      LabelExtractorDefinition.create!(
        module_name: 'galaxy_zoo',
        extractor_name: 'gztt',
        config: {
          build_custom_schema: true,
          task_key_label_prefixes: { T0: 'merger' },
          task_key_data_labels: { T0: { '0': 'yes', '1': 'no', '2': 'artifact' } }
        }
      )
    end

    it 'includes the generated custom schema for training' do
      expect(described_class.for_training(context)).to include(
        custom_schema_json: generated_custom_schema.to_json
      )
    end

    it 'includes the generated custom schema for prediction' do
      expect(described_class.for_prediction(context)).to include(
        custom_schema_json: generated_custom_schema.to_json
      )
    end

    it 'ignores context-level custom schema metadata' do
      context.metadata['batch']['custom_schema_json'] = {
        'question_answer_pairs' => {
          'manual' => %w[_yes _no]
        },
        'dependencies' => {
          'manual' => nil
        }
      }.to_json

      expect(described_class.for_training(context)).to include(
        custom_schema_json: generated_custom_schema.to_json
      )
    end
  end
end
