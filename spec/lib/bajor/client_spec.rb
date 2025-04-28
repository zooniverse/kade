# frozen_string_literal: true

require 'bajor/client'
require 'rails_helper'

def build_expected_body(manifest_url: nil, manifest_path: nil, workflow_name:, fixed_crop: nil)
  run_opts = "--schema #{workflow_name}"
  run_opts += " --fixed_crop #{fixed_crop.to_json}" if fixed_crop

  opts = {
    workflow_name: workflow_name,
    run_opts: run_opts
  }

  if manifest_url
    { manifest_url: manifest_url, opts: opts }
  else
    { manifest_path: manifest_path, opts: opts }
  end
end

RSpec.describe Bajor::Client do
  let(:bajor_client) { described_class.new }
  let(:bajor_host) { 'https://bajor.zooniverse.org' }
  let(:run_opts) { '--schema cosmic_dawn' }
  let(:workflow_name) { 'cosmic_dawn' }
  let(:request_headers) do
    {
      'Accept' => 'application/json',
      'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
      'Authorization' => 'Basic YmFqb3I6YmFqb3I=',
      'Content-Type' => 'application/json',
      'User-Agent' => 'Ruby'
    }
  end

  describe 'create_training_job' do
    let(:request_url) { "#{bajor_host}/training/jobs/" }
    let(:catalogue_manifest_path) { 'training_catalogues/manifest_path.csv' }
    let(:request_body) do
      {
        manifest_path: catalogue_manifest_path,
        opts: {
          run_opts: run_opts,
          workflow_name: workflow_name
        }
      }
    end
    let(:job_id) { '3ed68115-dc36-4f66-838c-a52869031676' }
    let(:bajor_response_body) do
      {
        'manifest_path' => catalogue_manifest_path,
        'id' => job_id,
        'status' => {
          'status' => 'submitted',
          'message' => 'Job submitted successfully'
        },
        'run_opts' => ''
      }
    end
    let(:request) do
      stub_request(:post, request_url)
        .with(
          body: request_body,
          headers: request_headers
        )
    end

    context 'with a success response' do
      before do
        request.to_return(status: 201, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
      end

      it 'correctly posts the manifest_path to bajor' do
        bajor_client.create_training_job(catalogue_manifest_path)
        expect(
          a_request(:post, request_url).with(body: request_body, headers: request_headers)
        ).to have_been_made.once
      end

      it 'returns the submitted job id as a batch job service url' do
        result = bajor_client.create_training_job(catalogue_manifest_path)
        expect(result).to eq("#{bajor_host}/training/job/#{job_id}")
      end
    end

    context 'with specific workflow_name' do
      let(:workflow_name) { 'euclid' }
      let(:run_opts) { '--schema euclid' }

      let(:request_body) do
        {
          manifest_path: catalogue_manifest_path,
          opts: {
            run_opts: run_opts,
            workflow_name: workflow_name
          }
        }
      end
      let(:request) do
        stub_request(:post, request_url)
          .with(
            body: request_body,
            headers: request_headers
          )
      end

      before do
        request.to_return(status: 201, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
      end

      it 'sends the right workflow name' do
        bajor_client.create_training_job(catalogue_manifest_path, { workflow_name: workflow_name })
        expect(
          a_request(:post, request_url).with(body: request_body, headers: request_headers)
        ).to have_been_made.once
      end

    end

    context 'with jswt_cosmos workflow and fixed crop' do
      let(:workflow_name) { 'jswt_cosmos' }
      let(:fixed_crop) do
        {
          lower_left_x: 30,
          lower_left_y: 30,
          upper_right_x: 750,
          upper_right_y: 750
        }
      end
      let(:expected_body) { build_expected_body(manifest_path: catalogue_manifest_path, workflow_name: workflow_name, fixed_crop: fixed_crop) }
      let(:request) do
        stub_request(:post, request_url)
          .with(
            body: expected_body.to_json,
            headers: request_headers
          )
      end

      before do
        request.to_return(status: 201, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
      end

      it 'sends jswt_cosmos workflow and fixed_crop settings' do
        bajor_client.create_training_job(
          catalogue_manifest_path,
          { workflow_name: workflow_name, fixed_crop: fixed_crop }
        )
        expect(
          a_request(:post, request_url)
            .with(body: expected_body, headers: request_headers)
        ).to have_been_made.once
      end
    end

    context 'with jswt_cosmos workflow and no fixed crop' do
      let(:workflow_name) { 'jswt_cosmos' }
      let(:expected_body) { build_expected_body(manifest_path: catalogue_manifest_path, workflow_name: workflow_name) }
      let(:request) do
        stub_request(:post, request_url)
          .with(
            body: expected_body.to_json,
            headers: request_headers
          )
      end

      before do
        request.to_return(status: 201, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
      end

      it 'sends jswt_cosmos workflow without fixed_crop settings' do
        bajor_client.create_training_job(
          catalogue_manifest_path,
          { workflow_name: workflow_name }
        )
        expect(
          a_request(:post, request_url)
            .with(body: expected_body, headers: request_headers)
        ).to have_been_made.once
      end
    end

    context 'with a failed repsonse' do
      let(:error_message) do
        'Active Jobs are running in the batch system - please wait till they are fininshed processing.'
      end
      let(:error_response) do
        {
          'state' => 'error',
          'message' => error_message
        }
      end

      before do
        request.to_return(status: 409, body: error_response.to_json, headers: { content_type: 'application/json' })
      end

      it 'raises an error' do
        expect { bajor_client.create_training_job(catalogue_manifest_path) }.to raise_error(Bajor::Client::Error, error_message)
      end
    end
  end

  describe 'create_prediction_job' do
    let(:request_url) { "#{bajor_host}/prediction/jobs/" }
    let(:manifest_url) { 'https://manifest-host.zooniverse.org/manifest.csv' }
    let(:run_opts) { '--schema cosmic_dawn' }
    let(:request_body) do
      {
        manifest_url: manifest_url,
        opts: {
          workflow_name: workflow_name,
          run_opts: run_opts
        }
      }
    end
    let(:job_id) { '3ed68115-dc36-4f66-838c-a52869031c9c' }
    let(:bajor_response_body) do
      {
        'manifest_url' => manifest_url,
        'id' => job_id,
        'status' => {
          'status' => 'submitted',
          'message' => 'Job submitted successfully'
        },
        'run_opts' => ''
      }
    end
    let(:request) do
      stub_request(:post, request_url)
        .with(
          body: request_body,
          headers: request_headers
        )
    end

    context 'with a success response' do
      before do
        request.to_return(status: 201, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
      end

      it 'correctly posts the prediction job to bajor' do
        bajor_client.create_prediction_job(manifest_url)
        expect(
          a_request(:post, request_url).with(body: request_body, headers: request_headers)
        ).to have_been_made.once
      end

      it 'returns the submitted job id as a batch job service url' do
        result = bajor_client.create_prediction_job(manifest_url)
        expect(result).to eq("#{bajor_host}/prediction/job/#{job_id}")
      end
    end

    context 'with specific workflow_name' do
      let(:workflow_name) { 'euclid' }
      let(:run_opts) { '--schema euclid' }

      let(:request_body) do
        { manifest_url: manifest_url, opts: { workflow_name:, run_opts:} }
      end

      let(:request) do
        stub_request(:post, request_url)
          .with(
            body: request_body,
            headers: request_headers
          )
      end

      before do
        request.to_return(status: 201, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
      end

      it 'sends the right workflow name' do
        bajor_client.create_prediction_job(manifest_url, { workflow_name:, run_opts: })
        expect(
          a_request(:post, request_url).with(body: request_body, headers: request_headers)
        ).to have_been_made.once
      end
    end

    context 'with jswt_cosmos workflow and fixed crop' do
      let(:workflow_name) { 'jswt_cosmos' }
      let(:fixed_crop) do
        {
          lower_left_x: 30,
          lower_left_y: 30,
          upper_right_x: 750,
          upper_right_y: 750
        }
      end

      let(:expected_body) { build_expected_body(manifest_url: manifest_url, workflow_name: workflow_name, fixed_crop: fixed_crop) }

      let(:request) do
        stub_request(:post, request_url)
          .with(
            body: expected_body.to_json,
            headers: request_headers
          )
      end

      before do
        request.to_return(status: 201, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
      end

      it 'sends jswt_cosmos workflow and fixed_crop settings' do
        bajor_client.create_prediction_job(
          manifest_url,
          { workflow_name: workflow_name, fixed_crop: fixed_crop }
        )
        expect(
          a_request(:post, request_url)
            .with(body: expected_body.to_json, headers: request_headers)
        ).to have_been_made.once
      end
    end

    context 'with jswt_cosmos workflow and no fixed crop' do
      let(:workflow_name) { 'jswt_cosmos' }
      let(:expected_body) { build_expected_body(manifest_url: manifest_url, workflow_name: workflow_name) }
      let(:request) do
        stub_request(:post, request_url)
          .with(
            body: expected_body.to_json,
            headers: request_headers
          )
      end

      before do
        request.to_return(status: 201, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
      end

      it 'sends jswt_cosmos workflow without fixed_crop settings' do
        bajor_client.create_prediction_job(
          manifest_url,
          { workflow_name: workflow_name }
        )
        expect(
          a_request(:post, request_url)
            .with(body: expected_body, headers: request_headers)
        ).to have_been_made.once
      end
    end

    context 'with a failed repsonse' do
      let(:error_message) do
        'Active Jobs are running in the batch system - please wait till they are fininshed processing.'
      end
      let(:error_response) do
        {
          'state' => 'error',
          'message' => error_message
        }
      end

      before do
        request.to_return(status: 409, body: error_response.to_json, headers: { content_type: 'application/json' })
      end

      it 'raises an error' do
        expect { bajor_client.create_prediction_job(manifest_url) }.to raise_error(Bajor::Client::Error, error_message)
      end
    end

    describe 'prediction_job_results' do
      let(:job_id) { '64bf4fab-ed6d-4f9a-b8ae-004086e3676f' }
      let(:request_url) { "#{bajor_host}/prediction/job/#{job_id}" }
      let(:task_execution_info) do
        {
          'result' =>	'success',
          'start_time' =>	'2022-10-21T09:13:56.674045Z',
          'end_time' =>	'2022-10-21T09:14:02.071913Z',
          'exit_code' =>	0
        }
      end
      let(:bajor_response_body) do
        # these are partial responses from the bajor client
        # for more details lookup a prediction job in bajor
        # https://bajor-staging.zooniverse.org/prediction/jobs
        # or
        # https://learn.microsoft.com/en-us/rest/api/batchservice/job/get?tabs=HTTP#cloudjob
        # https://learn.microsoft.com/en-us/rest/api/batchservice/job/get?tabs=HTTP#jobstate
        {
          'id' => '64bf4fab-ed6d-4f9a-b8ae-004086e3676f',
          'uses_task_dependencies' => false,
          'url' => 'https://zoobot.eastus.batch.azure.com/jobs/64bf4fab-ed6d-4f9a-b8ae-004086e3676f',
          'e_tag' => '0x8DAB338D6CDA85D',
          'last_modified' => '2022-10-21T07:49:52.968918Z',
          'creation_time' => '2022-10-21T07:39:47.824823Z',
          'state' => 'completed',
          'state_transition_time' => '2022-10-21T07:49:53.759572Z',
          'previous_state' => 'active',
          'previous_state_transition_time' => '2022-10-21T07:39:47.854818Z',
          'priority' => 0,
          'allow_task_preemption' => false,
          'max_parallel_tasks' => -1,
          'common_environment_settings' => [
            {
              'name' => 'PREDICTIONS_JOB_RESULTS_DIR',
              'value' => 'jobs/2022-10-21T07:39_64bf4fab-ed6d-4f9a-b8ae-004086e3676f/results'
            }
          ],
          # Bajor helpfully includes the job tasks in it's job response
          # https://learn.microsoft.com/en-us/rest/api/batchservice/task/get?tabs=HTTP
          # https://learn.microsoft.com/en-us/rest/api/batchservice/task/get?tabs=HTTP#cloudtask
          'tasks' => [
            {
              'id' => '1',
              'state' => 'completed',
              'state_transition_time' => '2022-10-21T07:49:50.213937Z',
              'previous_state' => 'running',
              'previous_state_transition_time' => '2022-10-21T07:49:32.360748Z',
              'execution_info' => task_execution_info
            }
          ]
        }
      end
      let(:results_url) do
        'https://kadeactivelearning.blob.core.windows.net/predictions/jobs/2022-10-21T07:39_64bf4fab-ed6d-4f9a-b8ae-004086e3676f/results/predictions.json'
      end
      let(:request) do
        stub_request(:get, request_url).with(headers: request_headers)
      end

      context 'with a success response' do
        before do
          request.to_return(status: 200, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
        end

        it 'returns the job results blob storage url' do
          result = bajor_client.prediction_job_results(job_id)
          expect(result).to eq(results_url)
        end
      end

      context 'when the task has not completed' do
        let(:task_execution_info) do
          {
            'retryCount' =>	0,
            'requeueCount' => 0
          }
        end

        before do
          request.to_return(status: 200, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
        end

        it 'returns nil' do
          result = bajor_client.prediction_job_results(job_id)
          expect(result).to be_nil
        end
      end

      context 'with a failed response' do
        # set the task to failued status indicator - from the failure job that's about to run
        let(:task_execution_info) do
          {
            'result' =>	'failure',
            'start_time' =>	'2022-10-21T09:13:56.674045Z',
            'end_time' =>	'2022-10-21T09:14:02.071913Z',
            'exit_code' =>	1
          }
        end

        before do
          request.to_return(status: 200, body: bajor_response_body.to_json, headers: { content_type: 'application/json' })
        end

        it 'raises an error' do
          message = "One or more prediction job tasks failed - see job log details from: #{request_url}"
          expect { bajor_client.prediction_job_results(job_id) }.to raise_error(Bajor::Client::PredictionJobTaskError, message)
        end
      end
    end
  end
end
