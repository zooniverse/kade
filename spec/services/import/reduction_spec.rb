# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::Reduction do
  fixtures :contexts

  let(:context) { Context.first }
  let(:zooniverse_subject_id) { 999 }
  let(:payload_data) do
    {
      'id' => 4,
      'reducible' => {
        'id' => context.workflow_id,
        'type' => 'Workflow'
      },
      'data' => {
        '0' => 3, # smooth
        '1' => 9, # features or disk
        '2' => 0  # star or artifact
      },
      subject: {
        id: zooniverse_subject_id,
        'metadata' => { 'id' => '442940' },
        'created_at' => '2021-08-06T11:08:53.918Z',
        'updated_at' => '2021-08-06T11:08:53.918Z'
      },
      'task_key' => 'T0',
      'reducer_key' => 'internal_caesar_id_not_used_here',
      'created_at' => '2021-08-06T11:08:54.000Z',
      'updated_at' => '2021-08-06T11:08:54.000Z'
    }
  end
  let(:raw_payload) { ActionController::Parameters.new(payload_data) }

  describe '.run' do
    let(:expected_labels) do
      {
        'smooth-or-featured-cd_smooth' => 3,
        'smooth-or-featured-cd_featured-or-disk' => 9,
        'smooth-or-featured-cd_problem' => 0
      }
    end
    let(:task_schema_lookup_key) { 'T0' }
    let(:label_extractor) { LabelExtractors::GalaxyZoo::CosmicDawn.new(task_schema_lookup_key) }
    let(:reduction_model) { described_class.new(raw_payload, label_extractor).run }

    it 'creates a valid Reduction model with the correct lables', :aggregate_failures do
      expect(reduction_model).to be_valid
      expect(reduction_model.labels).to match(expected_labels)
    end

    it 'creates a placeholder backfilling subject' do
      expect { reduction_model }.to change(Subject, :count).from(0).to(1)
    end

    it 'correctly sets up the placeholder backfilling subject' do
      expected_subject_attributes = { 'zooniverse_subject_id' => zooniverse_subject_id, 'context_id' => context.id }
      expect(reduction_model.subject.attributes).to include(expected_subject_attributes)
    end

    it 'correctly links existing known subjects' do
      subject = Subject.create(zooniverse_subject_id: zooniverse_subject_id, context_id: context.id)
      expect(reduction_model.subject_id).to match(subject.id)
    end

    it 'raises with an invalid payload' do
      expect {
        described_class.new({}, label_extractor).run
      }.to raise_error(Import::Reduction::InvalidPayload, 'missing workflow, subject_id or task_key')
    end

    describe 'extracting the unique identifier from subject metadata' do
      context 'cosmic dawn mission' do
        it 'extracts the name correctly from normal id' do
          reduction_model_staging = described_class.new(raw_payload, label_extractor).run
          expect(reduction_model_staging.unique_id).to match('442940')
        end

        it 'extracts the name correctly from hidden id' do
          raw_payload[:subject]['metadata']['!id'] = 'hidden-44294'
          raw_payload[:subject]['metadata'].delete('id')
          reduction_model_staging = described_class.new(raw_payload, label_extractor).run
          expect(reduction_model_staging.unique_id).to match('hidden-44294')
        end

        it 'extracts the name correctly from private id' do
          raw_payload[:subject]['metadata']['#id'] = 'private-44294'
          raw_payload[:subject]['metadata'].delete('id')
          reduction_model_staging = described_class.new(raw_payload, label_extractor).run
          expect(reduction_model_staging.unique_id).to match('private-44294')
        end
      end

      it 'extracts the name correctly for decals mission data' do
        raw_payload[:subject]['metadata']['#name'] = '8000_231121_468'
        raw_payload[:subject]['metadata'].delete('id')
        reduction_model_staging = described_class.new(raw_payload, label_extractor).run
        expect(reduction_model_staging.unique_id).to match('8000_231121_468')
      end

      it 'extracts the name correctly for staging env' do
        staging_payload = raw_payload.dup
        staging_payload_metadata = raw_payload[:subject]['metadata'].dup
        staging_payload_metadata['!SDSS_ID'] = '1237663785278570672'
        staging_payload[:subject]['metadata'] = staging_payload_metadata.except('id')
        reduction_model_staging = described_class.new(staging_payload, label_extractor).run
        expect(reduction_model_staging.unique_id).to match('1237663785278570672')
      end

      it 'falls back to the Zooniverse subject id when no metadata identifier exists' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        raw_payload[:subject]['metadata'].delete('id')
        reduction_model_staging = described_class.new(raw_payload, label_extractor).run
        expect(reduction_model_staging.unique_id).to match(zooniverse_subject_id.to_s)
      end
    end

    context 'with a existing duplicate reduction' do
      let(:updated_payload_data) { payload_data.dup }
      let(:updated_labels) do
        {
          'smooth-or-featured-cd_smooth' => 4,
          'smooth-or-featured-cd_problem' => 1,
          'smooth-or-featured-cd_featured-or-disk' => 10
        }
      end

      before do
        reduction_model
        updated_payload_data['data'] = { '0' => 4, '1' => 10, '2' => 1 }
      end

      it 'upserts changed data', :aggregate_failures do
        updated_reduction = described_class.new(ActionController::Parameters.new(updated_payload_data), label_extractor).run
        expect(updated_reduction.labels).to match(updated_labels)
        expect(updated_reduction.raw_payload['data']).to match(updated_payload_data['data'])
      end
    end
  end
end
