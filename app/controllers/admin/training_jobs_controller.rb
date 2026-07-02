# frozen_string_literal: true

module Admin
  class TrainingJobsController < BaseController
    def index
      @training_jobs, @pagination = paginate(TrainingJob.order(id: :desc))
    end

    def show
      @training_job = TrainingJob.find(params[:id])
    end
  end
end
