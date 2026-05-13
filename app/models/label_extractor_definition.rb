# frozen_string_literal: true

class LabelExtractorDefinition < ApplicationRecord
  validates :module_name, :extractor_name, presence: true
  validates :extractor_name, uniqueness: { scope: :module_name }
  validates :config, presence: true
  validate :config_shape

  scope :enabled, -> { where(enabled: true) }

  def self.find_enabled(module_name, extractor_name)
    enabled.find_by(module_name: module_name, extractor_name: extractor_name)
  end

  private

  def config_shape
    LabelExtractors::ConfigurableExtractor.validate_config!(config)
  rescue LabelExtractors::ConfigurationError => e
    errors.add(:config, e.message)
  end
end
