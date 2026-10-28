# frozen_string_literal: true

class PredictionJob < ApplicationRecord
  belongs_to :context, optional: true

  validates :manifest_url, presence: true
  validates :state, inclusion: { in: %w[pending submitted failed completed], allow_nil: true }

  def completed?
    state == 'completed'
  end

  def submitted?
    state == 'submitted'
  end

  def failed?
    state == 'failed'
  end

  def job_id
    File.basename(service_job_url)
  end
end
