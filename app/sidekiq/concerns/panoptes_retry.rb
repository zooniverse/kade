# frozen_string_literal: true

module PanoptesRetry
  extend ActiveSupport::Concern

  def with_panoptes_retry(max_retries: 3)
    attempts = 0

    Sync do
      yield
    rescue Panoptes::Client::ServerError => e
      attempts += 1
      raise e if attempts >= max_retries

      sleep(rand(max_retries))
      retry
    ensure
      Faraday.default_connection.close
    end
  end
end
