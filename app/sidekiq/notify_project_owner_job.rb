# frozen_string_literal: true
require 'panoptes/api'

class NotifyProjectOwnerJob
  include Sidekiq::Job
  sidekiq_options retry: 5

  def perform(subject_set_id, completion_rate)
    @context = Context.find_by!(active_subject_set_id: subject_set_id)

    owner_link = fetch_project_owner
    owner_user = fetch_owner_user(owner_link['id'])

    ProjectNotificationMailer
      .notify_subject_completion(owner_user, @context, (completion_rate * 100))
      .deliver_now
  end

  private
  def fetch_project_owner(max_retries = 3)
    with_api_retry(max_retries) do
      resp = Panoptes::Api.client.project(@context.project_id)
      resp['links']['owner']
    end
  end

  def fetch_owner_user(owner_id, max_retries = 3)
    with_api_retry(max_retries) do
      Panoptes::Api.client.user(owner_id)
    end
  end


  def with_api_retry(max_retries)
    attempts = 0

    begin
      yield
    rescue Panoptes::Client::ServerError => e
      attempts += 1
      raise if attempts > max_retries

      sleep(rand(max_retries))
      retry
    ensure
      Faraday.default_connection.close
    end
  end
end
