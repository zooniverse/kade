# frozen_string_literal: true

module LabelExtractors
  class ConfigurableExtractor
    attr_reader :task_lookup_key

    def initialize(task_lookup_key, config)
      @task_lookup_key = task_lookup_key
      @config = self.class.normalize_config(config)
      self.class.validate_config!(@config)
      validate_task_key!
    end

    def extract(data_hash)
      data_hash.transform_keys do |key|
        "#{task_prefix}-#{data_release_suffix}_#{data_payload_label(key)}"
      end
    end

    def self.question_answers_schema(config)
      normalized_config = normalize_config(config)
      validate_config!(normalized_config)
      task_key_label_prefixes = normalized_config.fetch('task_key_label_prefixes')
      task_key_data_labels = normalized_config.fetch('task_key_data_labels')
      data_release_suffix = normalized_config.fetch('data_release_suffix')

      task_key_label_prefixes.flat_map do |task_key, question_prefix|
        task_key_data_labels.fetch(task_key).values.map do |answer_suffix|
          "#{question_prefix}-#{data_release_suffix}_#{answer_suffix}"
        end
      end
    end

    def self.normalize_config(config)
      config.to_h.deep_stringify_keys
    end

    def self.validate_config!(config)
      raise ConfigurationError, 'config must be an object' unless config.is_a?(Hash)

      validate_string!(config, 'data_release_suffix')
      validate_hash!(config, 'task_key_label_prefixes')
      validate_hash!(config, 'task_key_data_labels')
      validate_task_mappings!(config)
    end

    def self.validate_string!(config, key)
      return if config[key].is_a?(String) && config[key].present?

      raise ConfigurationError, "#{key} must be a non-empty string"
    end

    def self.validate_hash!(config, key)
      return if config[key].is_a?(Hash) && config[key].present?

      raise ConfigurationError, "#{key} must be a non-empty object"
    end

    def self.validate_task_mappings!(config)
      prefixes = config.fetch('task_key_label_prefixes')
      labels = config.fetch('task_key_data_labels')
      raise ConfigurationError, 'task key mappings must match' unless prefixes.keys.sort == labels.keys.sort

      prefixes.each do |task_key, prefix|
        raise ConfigurationError, "task_key_label_prefixes.#{task_key} must be a non-empty string" unless prefix.is_a?(String) && prefix.present?

        task_labels = labels.fetch(task_key)
        raise ConfigurationError, "task_key_data_labels.#{task_key} must be a non-empty object" unless task_labels.is_a?(Hash) && task_labels.present?

        task_labels.each do |answer_key, answer_label|
          raise ConfigurationError, "task_key_data_labels.#{task_key}.#{answer_key} must be a non-empty string" unless answer_label.is_a?(String) && answer_label.present?
        end
      end
    end

    private

    def validate_task_key!
      return if task_key_label_prefixes.key?(task_lookup_key) && task_key_data_labels.key?(task_lookup_key)

      raise UnknownTaskKey, "key not found: #{task_lookup_key}"
    end

    def task_prefix
      task_key_label_prefixes.fetch(task_lookup_key)
    end

    def data_payload_label(key)
      label = task_key_data_labels.dig(task_lookup_key, key)
      raise UnknownLabelKey, "key not found: #{key}" unless label

      label
    end

    def data_release_suffix
      @config.fetch('data_release_suffix')
    end

    def task_key_label_prefixes
      @config.fetch('task_key_label_prefixes')
    end

    def task_key_data_labels
      @config.fetch('task_key_data_labels')
    end
  end
end
