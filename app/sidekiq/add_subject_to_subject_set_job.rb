# frozen_string_literal: true
require 'panoptes/api'
require 'concerns/panoptes_retry'

class AddSubjectToSubjectSetJob
  include Sidekiq::Job
  include PanoptesRetry

  def perform(subject_ids, subject_set_id, max_retries = 3)
    with_panoptes_retry(max_retries: max_retries) do
      Panoptes::Api.client.add_subjects_to_subject_set(subject_set_id, Array.wrap(subject_ids))
    end
  end
end
