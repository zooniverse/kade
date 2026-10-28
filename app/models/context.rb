class Context < ApplicationRecord
  CANDIDATE_SELECTION_DEFAULTS = {
    'probability_threshold' => 0.8, 'randomisation_factor' => 0.2
  }.freeze

  has_many :subjects, dependent: :restrict_with_exception
  has_many :candidate_subjects, dependent: :restrict_with_exception
  has_many :prediction_jobs, dependent: :restrict_with_exception

  validates :workflow_id, uniqueness: { scope: :project_id, message: 'Workflow and project must be unique' }
  validates :prediction_source, inclusion: { in: %w[panoptes_subject_set azure_catalogue] }
  validates :pool_subject_set_id, presence: true, unless: :azure_catalogue?
  validates :project_id, :workflow_id, :active_subject_set_id, presence: true, if: :azure_catalogue?
  validate :validate_candidate_selection, if: :azure_catalogue?

  def azure_catalogue?
    prediction_source == 'azure_catalogue'
  end

  def candidate_selection
    CANDIDATE_SELECTION_DEFAULTS.merge((metadata || {}).fetch('selection', {}))
  end

  private

  def validate_candidate_selection
    raise ArgumentError, 'metadata and selection must be objects' unless
      (metadata.nil? || metadata.is_a?(Hash)) && (metadata || {}).fetch('selection', {}).is_a?(Hash)

    settings = candidate_selection
    unknown = settings.keys - CANDIDATE_SELECTION_DEFAULTS.keys
    raise ArgumentError, "unknown selection settings: #{unknown.join(', ')}" if unknown.any?
    %w[probability_threshold randomisation_factor].each do |key|
      value = settings[key]
      raise ArgumentError, "#{key} must be between 0 and 1" unless
        value.is_a?(Numeric) && value.finite? && value.between?(0, 1)
    end
  rescue ArgumentError => e
    errors.add(:metadata, e.message)
  end
end
