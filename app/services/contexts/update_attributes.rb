# frozen_string_literal: true

module Contexts
  class UpdateAttributes
    class ValidationError < StandardError; end

    CONTEXT_ATTRIBUTE_KEYS = %w[
      workflow_id
      project_id
      active_subject_set_id
      pool_subject_set_id
      module_name
      extractor_name
    ].freeze
    INTEGER_ATTRIBUTE_KEYS = %w[
      workflow_id
      project_id
      active_subject_set_id
      pool_subject_set_id
    ].freeze

    def initialize(context:, params:)
      @context = context
      @params = normalize_params(params)
    end

    def call
      validate!

      attributes = params.slice(*CONTEXT_ATTRIBUTE_KEYS)

      if params.key?('metadata')
        metadata = current_metadata.deep_merge(params.fetch('metadata').to_h)
        validate_batch_metadata!(metadata['batch']) if params.fetch('metadata').to_h.key?('batch')
        attributes['metadata'] = metadata
      end

      context.update!(attributes)
      context
    end

    private

    attr_reader :context, :params

    def normalize_params(raw_params)
      hash =
        if raw_params.respond_to?(:to_unsafe_h)
          raw_params.to_unsafe_h
        elsif raw_params.respond_to?(:to_h)
          raw_params.to_h
        else
          {}
        end

      hash.deep_stringify_keys.slice(*CONTEXT_ATTRIBUTE_KEYS, 'metadata')
    end

    def validate!
      raise ValidationError, 'at least one supported context field is required' if params.empty?

      if params.key?('metadata') && !params['metadata'].respond_to?(:to_h)
        raise ValidationError, 'metadata must be an object'
      end

      INTEGER_ATTRIBUTE_KEYS.each { |key| validate_integer_param!(key) if params.key?(key) }
      validate_extractor_pair!
    end

    def current_metadata
      context.metadata.is_a?(Hash) ? context.metadata.deep_dup : {}
    end

    def validate_batch_metadata!(batch_config)
      return if batch_config.nil?

      unless batch_config.respond_to?(:to_h)
        raise ValidationError, 'metadata.batch must be an object'
      end

      Batch::RuntimeConfig.validate!(batch_config)
    end

    def validate_extractor_pair!
      return unless params.key?('module_name') || params.key?('extractor_name')

      module_name = params.key?('module_name') ? params['module_name'] : context.module_name
      extractor_name = params.key?('extractor_name') ? params['extractor_name'] : context.extractor_name

      return if LabelExtractors::Registry.extractor_registered?(module_name, extractor_name)

      raise ValidationError, "unknown module/extractor pair: #{module_name}/#{extractor_name}"
    end

    def validate_integer_param!(key)
      value = params[key]
      return if value.is_a?(Integer)
      return if value.is_a?(String) && value.match?(/\A\d+\z/)

      raise ValidationError, "#{key} must be an integer"
    end
  end
end
