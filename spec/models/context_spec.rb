# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Context, type: :model do
  let(:attributes) do
    { project_id: 1, workflow_id: 1, active_subject_set_id: 1, pool_subject_set_id: 2 }
  end
  let(:context) { described_class.new(attributes) }

  it 'creates a valid model' do
    expect(context).to be_valid
  end

  it 'allows an Azure catalogue without a Panoptes pool set' do
    context.assign_attributes(prediction_source: 'azure_catalogue', pool_subject_set_id: nil)
    expect(context).to be_valid
  end

  it 'still requires a Panoptes pool for the existing source' do
    context.pool_subject_set_id = nil
    expect(context).not_to be_valid
  end

  it 'supplies the two POC selection defaults and accepts overrides' do
    expect(context.candidate_selection).to eq(
      'probability_threshold' => 0.8, 'randomisation_factor' => 0.2
    )
    context.metadata = { selection: { probability_threshold: 0.6 } }
    expect(context.candidate_selection).to eq(
      'probability_threshold' => 0.6, 'randomisation_factor' => 0.2
    )
  end

  it 'rejects invalid probability settings and removed configuration options' do
    [{ probability_threshold: 1.1 }, { randomisation_factor: -0.1 },
     { randomisation_factor: '0.2' }, { frame_combination: 'max' }, { sample: '1' }, { score_path: [1] }].each do |selection|
      context.assign_attributes(prediction_source: 'azure_catalogue', metadata: { selection: selection })
      expect(context).not_to be_valid
    end
  end

  it 'requires metadata and selection to be objects' do
    [[], { selection: [] }, { selection: nil }].each do |metadata|
      context.assign_attributes(prediction_source: 'azure_catalogue', metadata: metadata)
      expect(context).not_to be_valid
    end
  end

  it 'does not allow duplicate workflow project ids' do
    context.save!
    dup = described_class.new(attributes)
    dup.valid?
    expect(dup.errors[:workflow_id]).to include('Workflow and project must be unique')
  end

  it 'does not raise an error deleting without subjects' do
    expect { context.destroy }.not_to raise_error
  end

  describe '.subjects' do
    let(:subject_model) do
      Subject.create({ zooniverse_subject_id: 1, context_id: context.id })
    end

    before do
      context.save
      subject_model
    end

    it 'correctly links the association' do
      expect(context.subjects).to match_array([subject_model])
    end

    it 'raises an error when destroying' do
      expect { context.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError, 'Cannot delete record because of dependent subjects')
    end
  end
end
