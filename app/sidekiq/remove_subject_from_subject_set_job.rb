# frozen_string_literal: true

require 'panoptes/api'
require 'concerns/panoptes_retry'

class RemoveSubjectFromSubjectSetJob
  include Sidekiq::Job
  include PanoptesRetry

  def perform(subject_ids, subject_set_id, max_retries=3)
    # format the subject ids into a comma separated string
    # which the API expects for the destroy_links action
    linked_subject_ids = Array.wrap(subject_ids).join(',')
    # as the client subject set resource doesn't offer this method
    # use the underlying client implementation to achieve it
    # longer term I should add this to the client...
    # apologies to all future selves for not doing so this time :sadpanda:
    with_panoptes_retry(max_retries: max_retries) do
      Panoptes::Api.client.panoptes.delete("/subject_sets/#{subject_set_id}/links/subjects/#{linked_subject_ids}")
    end
  end
end
