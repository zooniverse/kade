# frozen_string_literal: true

module Admin
  class ReductionsController < BaseController
    def index
      scope = Reduction.includes(:subject).order(id: :desc)
      scope = scope.where(zooniverse_subject_id: params[:zooniverse_subject_id]) if params[:zooniverse_subject_id].present?
      @reductions, @pagination = paginate(scope)
    end

    def show
      @reduction = Reduction.includes(:subject).find(params[:id])
    end
  end
end
