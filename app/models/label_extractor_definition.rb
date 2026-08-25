# frozen_string_literal: true

class LabelExtractorDefinition < ApplicationRecord
  before_validation :sanitize_inputs

  validates :module_name, :extractor_name, presence: true
  validates :extractor_name, uniqueness: { scope: :module_name }
  validates :config, presence: true
  validate :config_shape

  scope :enabled, -> { where(enabled: true) }

  def self.find_enabled(module_name, extractor_name)
    enabled.find_by(module_name: module_name, extractor_name: extractor_name)
  end

  private

  def sanitize_inputs
    self.module_name = sanitize_string(module_name) if module_name
    self.extractor_name = sanitize_string(extractor_name) if extractor_name
    self.config = sanitize_config_value(config) if config
  end

  def sanitize_config_value(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, config_value), sanitized|
        sanitized[sanitize_string(key.to_s)] = sanitize_config_value(config_value)
      end
    when Array
      value.map { |config_value| sanitize_config_value(config_value) }
    when String
      sanitize_string(value)
    else
      value
    end
  end

  def sanitize_string(value)
    ActionController::Base.helpers.strip_tags(value.to_s).strip
  end

  def config_shape
    LabelExtractors::ConfigurableExtractor.validate_config!(config)
  rescue LabelExtractors::ConfigurationError => e
    errors.add(:config, e.message)
  end
end
