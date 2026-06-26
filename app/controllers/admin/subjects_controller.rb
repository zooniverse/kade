# frozen_string_literal: true

module Admin
  class SubjectsController < BaseController
    def index
      scope = Subject.includes(:context, :reductions, :predictions).order(id: :desc)
      scope = scope.where(zooniverse_subject_id: params[:zooniverse_subject_id]) if params[:zooniverse_subject_id].present?
      @subjects, @pagination = paginate(scope)
    end

    def show
      @subject = Subject.includes(:context, :reductions, :predictions).find(params[:id])
    end
  end
end
