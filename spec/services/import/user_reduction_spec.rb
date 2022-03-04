# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::UserReduction do
  let(:raw_payload) do
    ActionController::Parameters.new(
      {
        'id' => 4,
        'reducible' => {
          'id' => 4,
          'type' => 'Workflow'
        },
        'data' => {
          '0' => 3, # smooth
          '1' => 9, # features or disk
          '2' => 0  # star or artifact
        },
        subject: {
          id: 4,
          'metadata' => {},
          'created_at' => '2021-08-06T11:08:53.918Z',
          'updated_at' => '2021-08-06T11:08:53.918Z'
        },
        'created_at' => '2021-08-06T11:08:54.000Z',
        'updated_at' => '2021-08-06T11:08:54.000Z'
      }
    )
  end

  describe '.run' do
    let(:label_extractor) { LabelExtractors::GalaxyZoo.new(raw_payload['data']) }
    let(:user_reduction_model) { described_class.new(raw_payload).run }

    it 'converts the raw reduction payload to a valid UserReduction model' do
      expect(user_reduction_model).to be_valid
    end

    it 'extracts the labels correctly' do
      expected_labels = ['smooth', 'features or disk', 'star or artifact']
      expect(user_reduction_model.labels).to match_array(expected_labels)
    end

    it 'raises with an invalid payload' do
      expect { described_class.new({}).run }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
