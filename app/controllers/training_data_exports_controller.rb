# frozen_string_literal: true

class TrainingDataExportsController < ApplicationController
  # as we're running in API mode we need to include basic auth
  include ActionController::HttpAuthentication::Basic::ControllerMethods

  http_basic_authenticate_with(
    name: Rails.application.config.api_basic_auth_username,
    password: Rails.application.config.api_basic_auth_password,
  )

  def index
    training_data_export_scope = TrainingDataExport.all.order(id: :desc).limit(params_page_size)
    render status: :ok, json: training_data_export_scope.to_json
  end

  def show
    training_data_export = TrainingDataExport.find(params[:id])
    render status: :ok, json: training_data_export.to_json
  end

  def create
    training_data_export = TrainingDataExport.create(
      storage_path: TrainingDataExport.storage_path(workflow_id),
      workflow_id: workflow_id
    )

    TrainingDataExporterJob.perform_async(training_data_export.id)

    render status: :created, json: training_data_export.to_json
  end

  private

  def training_data_export_params
    params.require(:training_data_export).permit(:workflow_id)
  end

  def workflow_id
    training_data_export_params[:workflow_id]
  end
end
