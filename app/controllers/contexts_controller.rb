# frozen_string_literal: true

class ContextsController < ApplicationController
  wrap_parameters false

  # as we're running in API mode we need to include basic auth
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  http_basic_authenticate_with(
    name: Rails.application.config.api_basic_auth_username,
    password: Rails.application.config.api_basic_auth_password
  )

  rescue_from Contexts::UpdateAttributes::ValidationError,
              Batch::RuntimeConfig::ValidationError,
              ActiveRecord::RecordInvalid do |e|
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
    context = Context.find(params[:id])
    Contexts::UpdateAttributes.new(context: context, params: context_params).call

    render(
      status: :ok,
      json: context.as_json
    )
  end

  private

  def context_params
    @context_params ||= params.permit(
      *Contexts::UpdateAttributes::CONTEXT_ATTRIBUTE_KEYS,
      :metadata,
      metadata: {}
    )
  end
end
