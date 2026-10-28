# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidatePool::ProcessResults do
  let(:context) do
    Context.create!(project_id: 1, workflow_id: 2, active_subject_set_id: 3, prediction_source: 'azure_catalogue')
  end
  let(:external_id) { 'training/catalogues/test/images/selected.jpg' }
  let(:locations) { [{ 'image/jpeg' => 'https://example.com/selected.jpg' }] }
  let(:metadata) { { '!filename' => 'selected.jpg' } }
  let!(:previous) do
    context.candidate_subjects.create!(external_id: 'training/catalogues/test/images/previous.jpg', zooniverse_subject_id: 202,
                                      locations: [{ 'image/jpeg' => 'https://example.com/previous.jpg' }])
  end
  let(:manifest) do
    [
      [locations.sole.values.sole, { project_id: 1, subject_id: external_id, mime_type: 'image/jpeg', metadata: metadata }.to_json],
      [previous.locations.sole.values.sole, { project_id: 1, subject_id: previous.external_id, mime_type: 'image/jpeg', metadata: {} }.to_json]
    ]
  end
  let(:job) do
    PredictionJob.create!(context: context, catalogue_snapshot: { 'project_id' => 1, 'selection' => context.candidate_selection },
                          manifest_url: 'https://example.com/manifest.json', results_url: 'https://example.com/results.json',
                          state: 'completed', subject_set_id: 3, probability_threshold: 0.8, randomisation_factor: 0)
  end
  let(:data) { { external_id => { '0' => [0.9] }, previous.external_id => { '0' => [0.2] } } }
  let(:api) { double('Panoptes transport') }
  let(:client) { instance_double(Panoptes::Client, panoptes: api) }
  let(:current_ids) { %w[202 999] }
  let(:service) { described_class.new(job, panoptes_client: client) }
  let(:mapping) { context.candidate_subjects.find_by!(external_id: external_id) }

  before do
    stub_request(:get, job.manifest_url).to_return { { body: manifest.to_json } }
    stub_request(:get, job.results_url).to_return { { body: { data: data }.to_json } }
    allow(client).to receive(:subject_set).with(3).and_return('links' => { 'project' => '1' })
    allow(client).to receive(:subjects).with(subject_set_id: 3) { current_ids.map { |id| { 'id' => id } } }
    allow(client).to receive(:add_subjects_to_subject_set)
    allow(api).to receive(:post).and_return('subjects' => [{ 'id' => '101' }])
    allow(api).to receive(:delete)
  end

  it 'saves only the selected image, registers its external URL, and removes owned deselected memberships' do
    expect { service.run }.to change(CandidateSubject, :count).by(1)
    expect(api).to have_received(:post).with('/subjects', subjects: {
      external_id: "kade-candidate-#{mapping.id}", links: { project: 1 },
      metadata: metadata.merge('#kade_candidate_id' => mapping.id.to_s), locations: locations
    })
    expect(mapping.zooniverse_subject_id).to eq(101)
    expect(mapping.registration_started_at).to be_present
    expect(client).to have_received(:add_subjects_to_subject_set).with(3, ['101'])
    expect(api).to have_received(:delete).with('/subject_sets/3/links/subjects/202')
    expect(job.reload.selection['scores'][external_id]).to eq(0.9)
    expect(job.applied_at).to be_present
  end

  it 'saves nothing for never-selected images and retains previously registered mappings' do
    data[external_id]['0'] = [0.2]
    expect { service.run }.not_to change(CandidateSubject, :count)
    expect(context.candidate_subjects.find_by(external_id: external_id)).to be_nil
    expect(previous.reload.zooniverse_subject_id).to eq(202)
    expect(api).not_to have_received(:post)
    expect(job.reload.selection['selected']).to be_empty
  end

  it 'reuses an existing mapping instead of registering again' do
    context.candidate_subjects.create!(external_id: external_id, metadata: metadata, locations: locations, zooniverse_subject_id: 101)
    expect { service.run }.not_to change(CandidateSubject, :count)
    expect(api).not_to have_received(:post)
    expect(client).to have_received(:add_subjects_to_subject_set).with(3, ['101'])
  end

  it 'keeps an existing membership without adding it again' do
    context.candidate_subjects.create!(external_id: external_id, metadata: metadata, locations: locations, zooniverse_subject_id: 101)
    current_ids << '101'
    service.run
    expect(client).not_to have_received(:add_subjects_to_subject_set)
  end

  it 'removes a previously registered member even if its blob is absent from this manifest' do
    manifest.pop
    data.delete(previous.external_id)
    service.run
    expect(api).to have_received(:delete).with('/subject_sets/3/links/subjects/202')
    expect(previous.reload.zooniverse_subject_id).to eq(202)
  end

  it 'uses the exported image metadata without listing Azure or relying on database catalogue rows' do
    expect(CandidatePool::SyncAzure).not_to receive(:new)
    service.run
    expect(mapping.metadata).to eq(metadata)
    expect(mapping.locations).to eq(locations)
  end

  it 'selects a subject whose score equals the threshold' do
    data[external_id]['0'] = [0.8]
    service.run
    expect(job.reload.selection['selected']).to eq([external_id])
  end

  it 'ignores prediction samples after sample 0' do
    data[external_id]['1'] = [0.99]
    data[external_id]['0'] = [0.2]
    service.run
    expect(job.reload.selection['scores'][external_id]).to eq(0.2)
    expect(api).not_to have_received(:post)
  end

  it 'rejects a missing sample or score before saving mappings or changing Panoptes' do
    [{}, { '0' => [] }, nil].each do |result|
      data[external_id] = result
      expect { service.run }.to raise_error(ArgumentError, /sample 0/)
    end
    expect(context.candidate_subjects.count).to eq(1)
    expect(api).not_to have_received(:post)
    expect(api).not_to have_received(:delete)
  end

  it 'rejects scores outside the probability range' do
    [-0.1, 1.1, nil, 'bad'].each do |score|
      data[external_id] = { '0' => [score] }
      expect { service.run }.to raise_error(ArgumentError, /finite number/)
    end
    expect(api).not_to have_received(:post)
  end

  it 'rejects missing or unexpected result identities before saving mappings or changing memberships' do
    data.delete(external_id)
    data['unexpected'] = { '0' => [0.9] }
    expect { service.run }.to raise_error(ArgumentError, /every candidate subject/)
    expect(job.reload.selection).to be_nil
    expect(context.candidate_subjects.count).to eq(1)
    expect(api).not_to have_received(:post)
    expect(api).not_to have_received(:delete)
  end

  it 'rejects duplicate manifest identities' do
    manifest << manifest.first
    expect { service.run }.to raise_error(ArgumentError, /unique subject IDs/)
    expect(api).not_to have_received(:post)
  end

  it 'rejects an empty manifest instead of removing all current memberships' do
    manifest.clear
    data.clear
    expect { service.run }.to raise_error(ArgumentError, /nonempty array/)
    expect(api).not_to have_received(:delete)
    expect(job.reload.selection).to be_nil
  end

  it 'validates every selected image before registering any of them' do
    manifest << ['http://example.com/bad.jpg', {
      project_id: 1, subject_id: 'bad', mime_type: 'image/jpeg', metadata: {}
    }.to_json]
    data['bad'] = { '0' => [0.9] }
    expect { service.run }.to raise_error(ActiveRecord::RecordInvalid)
    expect(context.candidate_subjects.count).to eq(1)
    expect(api).not_to have_received(:post)
    expect(api).not_to have_received(:delete)
  end

  it 'rejects a manifest belonging to another project' do
    manifest.first[1] = JSON.parse(manifest.first.last).merge('project_id' => 99).to_json
    expect { service.run }.to raise_error(ArgumentError, /prediction project/)
    expect(api).not_to have_received(:post)
  end

  it 'does not write mappings if the manifest cannot be downloaded' do
    stub_request(:get, job.manifest_url).to_return(status: 404)
    expect { service.run }.to raise_error(StandardError)
    expect(context.candidate_subjects.count).to eq(1)
    expect(api).not_to have_received(:post)
  end

  it 'rejects invalid selected image URLs before any registration or membership changes' do
    manifest.first[0] = 'https://example.com/selected.jpg?sig=expired'
    expect { service.run }.to raise_error(ActiveRecord::RecordInvalid)
    expect(context.candidate_subjects.count).to eq(1)
    expect(api).not_to have_received(:post)
    expect(api).not_to have_received(:delete)
  end

  it 'rejects changed media for an existing mapping instead of reusing the wrong Panoptes subject' do
    context.candidate_subjects.create!(external_id: external_id, metadata: metadata,
                                     locations: [{ 'image/png' => 'https://example.com/different.png' }], zooniverse_subject_id: 101)
    expect { service.run }.to raise_error(ArgumentError, /different media or metadata/)
    expect(api).not_to have_received(:delete)
    expect(client).not_to have_received(:add_subjects_to_subject_set)
  end

  it 'rejects a target subject set from a different project before saving mappings' do
    allow(client).to receive(:subject_set).and_return('links' => { 'project' => '99' })
    expect { service.run }.to raise_error(ArgumentError, /project/)
    expect(context.candidate_subjects.count).to eq(1)
    expect(api).not_to have_received(:post)
  end

  it 'saves a registration attempt before sending the request and blocks ambiguous retries' do
    allow(api).to receive(:post) do
      expect(mapping.registration_started_at).to be_present
      raise Timeout::Error
    end
    expect { service.run }.to raise_error(Timeout::Error)
    expect(mapping.reload.zooniverse_subject_id).to be_nil
    expect { service.run }.to raise_error(ArgumentError, /unresolved registration/)
    expect(api).to have_received(:post).once
  end

  it 'samples under-threshold subjects once and preserves that decision after an apply failure' do
    job.update!(randomisation_factor: 1)
    allow(client).to receive(:add_subjects_to_subject_set).and_raise(StandardError, 'apply failed')
    expect { service.run }.to raise_error(StandardError, 'apply failed')
    expect(job.reload.selection['random_sample']).to eq([previous.external_id])
    expect(job.selection['selected']).to match_array([external_id, previous.external_id])
    allow(client).to receive(:add_subjects_to_subject_set)
    described_class.new(job, panoptes_client: client).run
    expect(api).not_to have_received(:delete)
    expect(api).to have_received(:post).once
  end

  it 'prevents an older retry from undoing a newer run after partial application' do
    allow(client).to receive(:add_subjects_to_subject_set).and_raise(StandardError, 'membership failed')
    expect { service.run }.to raise_error(StandardError, 'membership failed')
    current_ids << '101'
    newer = job.dup
    newer.selection = { 'selected' => [previous.external_id] }
    newer.save!
    allow(client).to receive(:add_subjects_to_subject_set)
    described_class.new(newer, panoptes_client: client).run

    service.run

    expect(job.reload.message).to eq("Superseded by prediction job #{newer.id}")
    expect(client).to have_received(:add_subjects_to_subject_set).with(3, ['101']).once
    expect(api).to have_received(:delete).with('/subject_sets/3/links/subjects/101').once
    expect(api).to have_received(:post).once
  end

end
