# frozen_string_literal: true

module LabelExtractors
  class ConfigurableExtractor
    attr_reader :task_lookup_key

    CUSTOM_SCHEMA_FLAG = 'build_custom_schema'
    SCHEMA_IDENTIFIER = /\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/

    def initialize(task_lookup_key, config)
      @task_lookup_key = task_lookup_key
      @config = self.class.normalize_config(config)
      self.class.validate_config!(@config)
      validate_task_key!
    end

    def extract(data_hash)
      data_hash.transform_keys do |key|
        self.class.label_column(task_prefix, data_payload_label(key), @config)
      end
    end

    def self.question_answers_schema(config)
      normalized_config = normalize_config(config)
      validate_config!(normalized_config)
      validate_custom_schema_config!(normalized_config) if build_custom_schema?(normalized_config)
      task_key_label_prefixes = normalized_config.fetch('task_key_label_prefixes')
      task_key_data_labels = normalized_config.fetch('task_key_data_labels')

      task_key_label_prefixes.flat_map do |task_key, question_prefix|
        task_key_data_labels.fetch(task_key).values.map do |answer_suffix|
          label_column(question_prefix, answer_suffix, normalized_config)
        end
      end
    end

    def self.custom_schema(config)
      normalized_config = normalize_config(config)
      validate_config!(normalized_config)
      return unless build_custom_schema?(normalized_config)

      validate_custom_schema_config!(normalized_config)
      pairs = question_answer_pairs(normalized_config)
      {
        'question_answer_pairs' => pairs,
        'dependencies' => schema_dependencies(normalized_config, pairs.keys)
      }
    end

    def self.build_custom_schema?(config)
      ActiveModel::Type::Boolean.new.cast(normalize_config(config)[CUSTOM_SCHEMA_FLAG])
    end

    def self.normalize_config(config)
      config.to_h.deep_stringify_keys
    end

    def self.validate_config!(config)
      raise ConfigurationError, 'config must be an object' unless config.is_a?(Hash)

      validate_hash!(config, 'task_key_label_prefixes')
      validate_hash!(config, 'task_key_data_labels')
      validate_task_mappings!(config)
      validate_string!(config, 'data_release_suffix') unless build_custom_schema?(config)
      validate_config_identifiers!(config)
      validate_dependencies_shape!(config)
      validate_custom_schema_dependencies!(config) if build_custom_schema?(config)
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

    def self.validate_custom_schema_config!(config)
      validate_hash!(config, 'task_key_label_prefixes')
      validate_hash!(config, 'task_key_data_labels')
      validate_task_mappings!(config)
      validate_config_identifiers!(config)
      validate_dependencies_shape!(config)
      validate_custom_schema_dependencies!(config)
    end

    def self.validate_config_identifiers!(config)
      task_key_label_prefixes = config.fetch('task_key_label_prefixes')
      task_key_data_labels = config.fetch('task_key_data_labels')

      task_key_label_prefixes.each do |task_key, question_prefix|
        validate_schema_identifier!(task_key, "task key #{task_key}")
        validate_schema_identifier!(question_prefix, "question #{question_prefix}")

        task_key_data_labels.fetch(task_key).each do |answer_key, answer_suffix|
          validate_schema_identifier!(answer_key, "answer key #{answer_key}")
          validate_schema_identifier!(schema_answer_suffix(answer_suffix).delete_prefix('_'), "answer #{schema_answer_suffix(answer_suffix)}")
        end
      end

      validate_schema_identifier!(config['data_release_suffix'], "data_release_suffix #{config['data_release_suffix']}") if config['data_release_suffix'].present?
    end

    def self.validate_dependencies_shape!(config)
      dependencies = config['dependencies']
      return unless dependencies

      raise ConfigurationError, 'dependencies must be an object' unless dependencies.is_a?(Hash)

      dependencies.each do |question_or_task_key, dependency|
        validate_schema_identifier!(question_or_task_key, "dependency question #{question_or_task_key}")
        next if dependency.nil?

        validate_schema_identifier!(dependency, "dependency #{dependency}")
      end
    end

    def self.validate_custom_schema_dependencies!(config)
      pairs = question_answer_pairs(config)
      schema_labels = pairs.flat_map do |question, answers|
        answers.map { |answer| "#{question}#{answer}" }
      end

      schema_dependencies(config, pairs.keys).each do |question, dependency|
        validate_schema_identifier!(question, "dependency question #{question}")
        next if dependency.nil?

        unless schema_labels.include?(dependency)
          raise ConfigurationError, "dependency #{dependency} must reference a generated schema label"
        end
      end
    end

    def self.validate_schema_identifier!(value, key)
      return if value.is_a?(String) && value.match?(SCHEMA_IDENTIFIER)

      raise ConfigurationError, "#{key} contains unsupported characters"
    end

    def self.label_column(question_prefix, answer_suffix, config)
      return "#{question_prefix}#{schema_answer_suffix(answer_suffix)}" if build_custom_schema?(config)

      "#{question_prefix}-#{config.fetch('data_release_suffix')}_#{answer_suffix}"
    end

    def self.question_answer_pairs(config)
      task_key_label_prefixes = config.fetch('task_key_label_prefixes')
      task_key_data_labels = config.fetch('task_key_data_labels')

      task_key_label_prefixes.each_with_object({}) do |(task_key, question_prefix), pairs|
        pairs[question_name(question_prefix, config)] = task_key_data_labels.fetch(task_key).values.map do |answer_suffix|
          schema_answer_suffix(answer_suffix)
        end
      end
    end

    def self.schema_dependencies(config, question_names)
      dependencies = question_names.each_with_object({}) { |question, all| all[question] = nil }
      configured_dependencies = config['dependencies']
      return dependencies unless configured_dependencies.is_a?(Hash)

      configured_dependencies.each do |question_or_task_key, dependency|
        dependencies[dependency_question_name(question_or_task_key, config)] = dependency
      end

      dependencies
    end

    def self.dependency_question_name(question_or_task_key, config)
      task_key_label_prefixes = config.fetch('task_key_label_prefixes')
      question_prefix = task_key_label_prefixes[question_or_task_key]
      return question_or_task_key unless question_prefix

      question_name(question_prefix, config)
    end

    def self.question_name(question_prefix, config)
      return question_prefix if build_custom_schema?(config)

      "#{question_prefix}-#{config.fetch('data_release_suffix')}"
    end

    def self.schema_answer_suffix(answer_suffix)
      answer_suffix = answer_suffix.to_s
      answer_suffix.start_with?('_') ? answer_suffix : "_#{answer_suffix}"
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
