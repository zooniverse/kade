# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrainingJob, type: :model do
  let(:manifest_url) do
    'https://manifest-host.zooniverse.org/manifest.csv'
  end
  let(:attributes) do
    { manifest_url: manifest_url }
  end
  let(:model) { described_class.new(attributes) }

  it 'creates a valid model' do
    expect(model).to be_valid
  end

  it 'is invalid without a manifest_url' do
    model.manifest_url = nil
    expect(model).to be_invalid
  end

  it 'only allows specific state values', :aggregate_failures do
    %w[pending submitted failed completed].each do |state|
      model.state = state
      expect(model).to be_valid
    end
    model.state = nil
    expect(model).to be_valid
    model.state = :finished
    expect(model).to be_invalid
  end
end
