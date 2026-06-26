# frozen_string_literal: true

module Contexts
  class CreateAttributes
    class ValidationError < StandardError; end

    def initialize(params:)
      @params = normalize_params(params)
    end

    def call
      validate!

      attributes = params.slice(*UpdateAttributes::CONTEXT_ATTRIBUTE_KEYS)
      attributes['metadata'] = params['metadata'].to_h if params.key?('metadata')

      Context.create!(attributes)
    end

    private

    attr_reader :params

    def normalize_params(raw_params)
      hash =
        if raw_params.respond_to?(:to_unsafe_h)
          raw_params.to_unsafe_h
        elsif raw_params.respond_to?(:to_h)
          raw_params.to_h
        else
          {}
        end

      hash.deep_stringify_keys.slice(*UpdateAttributes::CONTEXT_ATTRIBUTE_KEYS, 'metadata')
    end

    def validate!
      raise ValidationError, 'at least one supported context field is required' if params.empty?

      if params.key?('metadata') && !params['metadata'].respond_to?(:to_h)
        raise ValidationError, 'metadata must be an object'
      end

      UpdateAttributes::INTEGER_ATTRIBUTE_KEYS.each { |key| validate_integer_param!(key) if params.key?(key) }
      validate_batch_metadata!(params.dig('metadata', 'batch')) if params.key?('metadata')
      validate_required_fields!
      validate_extractor_pair!
    end

    def validate_batch_metadata!(batch_config)
      return if batch_config.nil?

      unless batch_config.respond_to?(:to_h)
        raise ValidationError, 'metadata.batch must be an object'
      end

      Batch::RuntimeConfig.validate!(batch_config)
    end

    def validate_required_fields!
      required_keys = %w[
        workflow_id
        project_id
        active_subject_set_id
        pool_subject_set_id
        module_name
        extractor_name
      ]

      missing = required_keys.select { |key| params[key].blank? }
      raise ValidationError, "missing required context fields: #{missing.join(', ')}" if missing.any?
    end

    def validate_extractor_pair!
      return if LabelExtractors::Registry.extractor_registered?(params['module_name'], params['extractor_name'])

      raise ValidationError, "unknown module/extractor pair: #{params['module_name']}/#{params['extractor_name']}"
    end

    def validate_integer_param!(key)
      value = params[key]
      return if value.is_a?(Integer)
      return if value.is_a?(String) && value.match?(/\A\d+\z/)

      raise ValidationError, "#{key} must be an integer"
    end
  end
end
