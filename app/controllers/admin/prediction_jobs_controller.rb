# frozen_string_literal: true

module Admin
  class PredictionJobsController < BaseController
    def index
      @prediction_jobs, @pagination = paginate(PredictionJob.order(id: :desc))
    end

    def show
      @prediction_job = PredictionJob.find(params[:id])
    end
  end
end
