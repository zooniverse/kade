# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubjectsRetirementWorker, type: :job do
  describe '#perform' do
    let(:worker) { described_class.new }
    let(:context) { Context.first }
    let(:subject_set_id) { context.active_subject_set_id }

    before do
      allow(worker).to receive(:with_panoptes_retry).and_yield
      allow(NotifyProjectOwnerJob).to receive(:perform_async)
    end

    context 'when a context does not exist' do
      it 'returns early when no context is found' do
        local_subject_set_id = 20
        worker.perform(local_subject_set_id)

        expect(worker).not_to have_received(:with_panoptes_retry)
        expect(NotifyProjectOwnerJob).not_to have_received(:perform_async)
      end
    end

    context 'when a context with a workflow id exists' do
      let(:workflow_id) { context.workflow_id }
      let(:panoptes_client) { instance_double(Panoptes::Client) }

      before do
        allow(Panoptes::Api).to receive(:client).and_return(panoptes_client)
      end

      context 'and the Panoptes response lacks completeness' do
        before do
          allow(panoptes_client).to receive(:subject_set).with(subject_set_id).and_return('completeness' => {})
        end

        it 'does not enqueue a notification' do
          worker.perform(subject_set_id)
          expect(NotifyProjectOwnerJob).not_to have_received(:perform_async)
        end
      end

      context 'and the completion rate is below the threshold' do
        before do
          allow(panoptes_client).to receive(:subject_set).with(subject_set_id).and_return('completeness' => { workflow_id.to_s => 0.25 })
        end

        it 'does not enqueue a notification' do
          worker.perform(subject_set_id)
          expect(NotifyProjectOwnerJob).not_to have_received(:perform_async)
        end
      end

      context 'and the completion rate meets the threshold' do
        let(:completeness_value) { 0.96 }

        before do
          allow(panoptes_client).to receive(:subject_set).with(subject_set_id).and_return('completeness' => { workflow_id.to_s => completeness_value })
        end

        it 'enqueues a notification with the completion rate' do
          worker.perform(subject_set_id)
          expect(NotifyProjectOwnerJob).to have_received(:perform_async).with(subject_set_id, completeness_value)
          expect(worker).to have_received(:with_panoptes_retry).with(max_retries: 3)
        end
      end
    end
  end
end
