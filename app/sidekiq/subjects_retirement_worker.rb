# frozen_string_literal: true
require 'panoptes/api'
require 'concerns/panoptes_retry'

class SubjectsRetirementWorker
  include Sidekiq::Job
  include PanoptesRetry

  COMPLETION_NOTIFICATION_THRESHOLD = ENV.fetch('COMPLETION_NOTIFICATION_THRESHOLD', '0.95').to_f

  def perform(subject_set_id, max_retries = 3)
    context = Context.find_by(active_subject_set_id: subject_set_id)
    return unless context&.workflow_id

    workflow_id = context.workflow_id
    with_panoptes_retry(max_retries: max_retries) do
      resp = Panoptes::Api.client.subject_set(subject_set_id)
      completeness = resp.fetch('completeness', {})[workflow_id.to_s]
      notify_if_completion_threshold_met(subject_set_id, completeness)
    end
  end

  private

  def notify_if_completion_threshold_met(subject_set_id, completion_rate)
    return if completion_rate.nil?

    completion_rate = completion_rate.to_f
    if completion_rate >= COMPLETION_NOTIFICATION_THRESHOLD
      NotifyProjectOwnerJob.perform_async(subject_set_id, completion_rate)
    end
  end
end
