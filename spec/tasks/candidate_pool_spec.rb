# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'candidate_pool tasks' do
  let(:context) do
    Context.create!(project_id: 1, workflow_id: 2, active_subject_set_id: 3, prediction_source: 'azure_catalogue')
  end

  around do |example|
    original = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/candidate_pool.rake')
    example.run
  ensure
    Rake.application = original
  end

  it 'starts the existing prediction worker for an Azure context' do
    worker = instance_double(PredictionManifestExportJob, perform: nil)
    allow(PredictionManifestExportJob).to receive(:new).and_return(worker)
    Rake::Task['candidate_pool:predict'].invoke(context.id.to_s)
    expect(worker).to have_received(:perform).with(context.id)
  end

  it 'discovers Azure images without starting inference or contacting Panoptes' do
    sync = instance_double(CandidatePool::SyncAzure, run: [{ 'external_id' => 'a' }, { 'external_id' => 'b' }])
    allow(CandidatePool::SyncAzure).to receive(:new).with(context).and_return(sync)
    expect {
      Rake::Task['candidate_pool:sync'].invoke(context.id.to_s)
    }.to output("Discovered 2 image subjects for context #{context.id}\n").to_stdout
    expect(sync).to have_received(:run)
    expect(context.candidate_subjects).to be_empty
  end
end
