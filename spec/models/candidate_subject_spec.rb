# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateSubject do
  let(:context) do
    Context.create!(project_id: 1, workflow_id: 2, active_subject_set_id: 3, prediction_source: 'azure_catalogue')
  end
  let(:candidate) do
    context.candidate_subjects.build(external_id: 'training/catalogues/test/images/a.jpg',
                                     metadata: { '!filename' => 'a.jpg' }, locations: [
                                       { 'image/jpeg' => 'https://example.com/a.jpg' }
                                     ])
  end

  it 'stores a registration attempt and its Panoptes mapping' do
    candidate.update!(registration_started_at: Time.current)
    candidate.update!(zooniverse_subject_id: 101)
    expect(candidate.reload.zooniverse_subject_id).to eq(101)
    expect(candidate.registration_started_at).to be_present
  end

  it 'requires an identity unique within the context' do
    candidate.save!
    duplicate = candidate.dup
    expect(duplicate).not_to be_valid
    duplicate.external_id = ''
    expect(duplicate).not_to be_valid
  end

  it 'rejects multiple images' do
    candidate.locations *= 2
    expect(candidate).not_to be_valid
  end

  it 'requires permanent HTTPS image URLs without credentials or query strings' do
    ['https://example.com/a.jpg?sig=secret', 'https://user:pass@example.com/a.jpg',
     'https://example.com/a.jpg#fragment', 'file:///a.jpg'].each do |url|
      candidate.locations = [{ 'image/jpeg' => url }]
      expect(candidate).not_to be_valid
    end
  end

  it 'rejects empty locations, unsupported media and malformed metadata' do
    [[], [{ 'video/mp4' => 'https://example.com/a.mp4' }], ['https://example.com/a.jpg']].each do |locations|
      candidate.locations = locations
      expect(candidate).not_to be_valid
    end
    candidate.metadata = []
    expect(candidate).not_to be_valid
  end
end
