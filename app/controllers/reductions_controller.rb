# frozen_string_literal: true

class ReductionsController < ApplicationController
  # as we're running in API mode we need to include basic auth
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  # ensure we include the non model attributes in the reduction nested payload
  # https://api.rubyonrails.org/v7.0.2.3/classes/ActionController/ParamsWrapper.html
  wrap_parameters Reduction, include: %w[id reducible data subject]

  http_basic_authenticate_with(
    name: Rails.application.config.reduction_basic_auth_username,
    password: Rails.application.config.reduction_basic_auth_password,
    only: :create
  )

  http_basic_authenticate_with(
    name: Rails.application.config.api_basic_auth_username,
    password: Rails.application.config.api_basic_auth_password,
    only: %i[show index]
  )

  def index
    reduction_scope = Reduction.preload(:subject).order(id: :desc).limit(params_page_size)
    if params[:zooniverse_subject_id]
      reduction_scope = reduction_scope.where(zooniverse_subject_id: params[:zooniverse_subject_id])
    end
    render(
      status: :ok,
      json: reduction_scope.as_json(include: :subject)
    )
  end

  def show
    reduction = Reduction.preload(:subject).find(params[:id])
    render(
      status: :ok,
      json: reduction.as_json(include: :subject)
    )
  end

  def create
    label_extractor = LabelExtractors::Finder.extractor_instance(task_schema_lookup_key_param)
    # add the task lookup to the key payload
    reduction_params_with_task_key = reduction_params.merge('task_key' => task_schema_lookup_key_param)
    reduction = Import::Reduction.new(reduction_params_with_task_key, label_extractor).run
    render status: :created, json: reduction.to_json
  end

  private

  def reduction_params
    # as this API is internally facing only - ingesting from caesar, we have a controlled payload schema
    # so we can allow an open schema of the payload body / what can be saved to the db
    # longer term if needed we can look at validating via a json schema if required
    params.permit(reduction: {})[:reduction]
  end

  def task_schema_lookup_key_param
    params.permit(:task_schema_lookup_key)[:task_schema_lookup_key]
  end
end
