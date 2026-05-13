# frozen_string_literal: true

class ContextsController < ApplicationController
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
  wrap_parameters false

  # as we're running in API mode we need to include basic auth
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  http_basic_authenticate_with(
    name: Rails.application.config.api_basic_auth_username,
    password: Rails.application.config.api_basic_auth_password
  )

  rescue_from ValidationError do |e|
    json_error_render(:unprocessable_entity, e)
  end
  rescue_from Batch::RuntimeConfig::ValidationError do |e|
    json_error_render(:unprocessable_entity, e)
  end
  rescue_from ActiveRecord::RecordInvalid do |e|
    json_error_render(:unprocessable_entity, e)
  end

  def index
    contexts_scope = Context.order(id: :desc).limit(params_page_size)
    render(
      status: :ok,
      json: contexts_scope.as_json
    )
  end

  def show
    context = Context.find(params[:id])
    render(
      status: :ok,
      json: context.as_json
    )
  end

  def update
    validate_context_params!

    context = Context.find(params[:id])
    attributes = context_params.slice(*CONTEXT_ATTRIBUTE_KEYS)

    if context_params.key?('metadata')
      metadata = context_metadata(context).deep_merge(context_params.fetch('metadata').to_h)
      validate_batch_metadata!(metadata['batch']) if context_params.fetch('metadata').to_h.key?('batch')
      attributes[:metadata] = metadata
    end

    context.update!(attributes)

    render(
      status: :ok,
      json: context.as_json
    )
  end

  private

  def context_params
    @context_params ||= params.permit(
      *CONTEXT_ATTRIBUTE_KEYS,
      :metadata,
      metadata: {}
    )
  end

  def validate_context_params!
    raise ValidationError, 'at least one supported context field is required' if context_params.empty?

    if context_params.key?('metadata') && !context_params['metadata'].respond_to?(:to_h)
      raise ValidationError, 'metadata must be an object'
    end

    INTEGER_ATTRIBUTE_KEYS.each { |key| validate_integer_param!(key) if context_params.key?(key) }
    validate_extractor_pair!
  end

  def context_metadata(context)
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
    return unless context_params.key?('module_name') || context_params.key?('extractor_name')

    context = Context.find(params[:id])
    module_name = context_params.key?('module_name') ? context_params['module_name'] : context.module_name
    extractor_name = context_params.key?('extractor_name') ? context_params['extractor_name'] : context.extractor_name

    return if LabelExtractors::Registry.extractor_registered?(module_name, extractor_name)

    raise ValidationError, "unknown module/extractor pair: #{module_name}/#{extractor_name}"
  end

  def validate_integer_param!(key)
    value = context_params[key]
    return if value.is_a?(Integer)
    return if value.is_a?(String) && value.match?(/\A\d+\z/)

    raise ValidationError, "#{key} must be an integer"
  end
end
