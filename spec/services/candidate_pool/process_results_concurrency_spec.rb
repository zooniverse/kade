# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Candidate pool concurrent workers' do
  # Separate connections must see committed records and real PostgreSQL locks.
  self.use_transactional_tests = false

  let(:context_record) do
    Context.create!(project_id: 99_001, workflow_id: 99_001, active_subject_set_id: 3, prediction_source: 'azure_catalogue')
  end
  let(:job) do
    PredictionJob.create!(context: context_record, state: 'completed', subject_set_id: 3,
                          manifest_url: 'https://example.com/manifest.json',
                          catalogue_snapshot: { 'project_id' => context_record.project_id },
                          selection: { 'selected' => [] }, probability_threshold: 0.8, randomisation_factor: 0)
  end
  let(:api) { double('Panoptes transport', delete: nil) }
  let(:client) { instance_double(Panoptes::Client, panoptes: api) }

  before do
    @threads = []
    @release = Queue.new
    job
    allow(client).to receive(:subject_set).and_return('links' => { 'project' => context_record.project_id.to_s })
    allow(client).to receive(:subjects).and_return([])
    allow(client).to receive(:add_subjects_to_subject_set)
  end

  after do
    4.times { @release << true }
    @threads.each do |thread|
      thread.join(10)
      thread.kill.join if thread.alive?
    end
    PredictionJob.where(context_id: context_record.id).delete_all
    CandidateSubject.where(context_id: context_record.id).delete_all
    Context.where(id: context_record.id).delete_all
  end

  def start_worker(&block)
    ready = Queue.new
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        ready << connection.select_value('SELECT pg_backend_pid()')
        block.call
      end
    end
    @threads << thread
    [thread, Timeout.timeout(10) { ready.pop }]
  end

  def finish(thread)
    raise 'worker did not finish' unless thread.join(10)

    thread.value
  end

  def wait_for_lock_waiter(pid)
    Timeout.timeout(10) do
      loop do
        waiting = ActiveRecord::Base.connection.select_value(
          "SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid = #{Integer(pid)} AND locktype = 'advisory' AND NOT granted)"
        )
        break if waiting

        sleep 0.01
      end
    end
  end

  def block_reconciliation
    entered = Queue.new
    project_id = context_record.project_id.to_s
    allow(client).to receive(:subject_set) do
      entered << true
      Timeout.timeout(10) { @release.pop }
      { 'links' => { 'project' => project_id } }
    end
    entered
  end

  it 'atomically claims registration when two workers hold stale copies of the same candidate' do
    candidate = context_record.candidate_subjects.create!(
      external_id: 'training/images/a.jpg', locations: [{ 'image/jpeg' => 'https://example.com/a.jpg' }]
    )
    copies = 3.times.map { CandidateSubject.find(candidate.id) }
    entered = Queue.new
    ready = Queue.new
    start = Queue.new
    outcomes = Queue.new
    allow(api).to receive(:post) do
      entered << true
      Timeout.timeout(10) { @release.pop }
      { 'subjects' => [{ 'id' => '101' }] }
    end
    job_copy = job
    project_id = context_record.project_id
    workers = copies.first(2).map do |copy|
      start_worker do
        ready << true
        Timeout.timeout(10) { start.pop }
        begin
          CandidatePool::ProcessResults.new(job_copy, panoptes_client: client).send(:register, copy, project_id)
          outcomes << :registered
        rescue ArgumentError => e
          outcomes << e.message
        end
      end.first
    end
    2.times { Timeout.timeout(10) { ready.pop } }
    2.times { start << true }
    Timeout.timeout(10) { entered.pop }

    expect(candidate.reload.registration_started_at).to be_present
    expect(Timeout.timeout(10) { outcomes.pop }).to include('unresolved registration')
    @release << true
    workers.each { |thread| finish(thread) }
    expect(candidate.reload.zooniverse_subject_id).to eq(101)

    # A stale retry must reload and reuse the winner's mapping, not overwrite it.
    CandidatePool::ProcessResults.new(job_copy, panoptes_client: client).send(:register, copies.last, project_id)
    expect(copies.last.zooniverse_subject_id).to eq(101)
    expect(api).to have_received(:post).once
  end

  it 'serializes duplicate deliveries and reloads applied_at after waiting for the context lock' do
    entered = block_reconciliation
    first_copy = PredictionJob.find(job.id)
    stale_copy = PredictionJob.find(job.id)
    first, = start_worker { CandidatePool::ProcessResults.new(first_copy, panoptes_client: client).run }
    Timeout.timeout(10) { entered.pop }
    second, second_pid = start_worker { CandidatePool::ProcessResults.new(stale_copy, panoptes_client: client).run }
    wait_for_lock_waiter(second_pid)

    @release << true
    finish(first)
    finish(second)

    expect(job.reload.applied_at).to be_present
    expect(client).to have_received(:subject_set).once
    expect(client).to have_received(:subjects).once
  end

  it 'prevents an older waiting run from overwriting the newer run that finished first' do
    older = PredictionJob.find(job.id)
    newer = job.dup
    newer.save!
    entered = block_reconciliation
    first, = start_worker { CandidatePool::ProcessResults.new(newer, panoptes_client: client).run }
    Timeout.timeout(10) { entered.pop }
    second, second_pid = start_worker { CandidatePool::ProcessResults.new(older, panoptes_client: client).run }
    wait_for_lock_waiter(second_pid)

    @release << true
    finish(first)
    finish(second)

    expect(newer.reload.applied_at).to be_present
    expect(older.reload.applied_at).to be_nil
    expect(older.message).to eq("Superseded by prediction job #{newer.id}")
    expect(client).to have_received(:subject_set).once
  end

  it 'releases the context lock after failure and retains a registration for a retry on another connection' do
    external_id = 'training/images/a.jpg'
    job.update!(selection: { 'selected' => [external_id] })
    manifest = [['https://example.com/a.jpg', {
      project_id: context_record.project_id, subject_id: external_id, mime_type: 'image/jpeg', metadata: {}
    }.to_json]]
    stub_request(:get, job.manifest_url).to_return(body: manifest.to_json)
    allow(api).to receive(:post).and_return('subjects' => [{ 'id' => '101' }])
    allow(client).to receive(:add_subjects_to_subject_set).and_raise(StandardError, 'membership failed')
    first_copy = PredictionJob.find(job.id)
    first, = start_worker do
      begin
        CandidatePool::ProcessResults.new(first_copy, panoptes_client: client).run
      rescue StandardError => e
        e.message
      end
    end
    expect(finish(first)).to eq('membership failed')
    expect(context_record.candidate_subjects.sole.zooniverse_subject_id).to eq(101)
    expect(job.reload.applied_at).to be_nil

    allow(client).to receive(:add_subjects_to_subject_set)
    retry_copy = PredictionJob.find(job.id)
    second, = start_worker { CandidatePool::ProcessResults.new(retry_copy, panoptes_client: client).run }
    finish(second)

    expect(job.reload.applied_at).to be_present
    expect(api).to have_received(:post).once
  end
end
