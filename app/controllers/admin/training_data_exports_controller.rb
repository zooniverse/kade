# frozen_string_literal: true

module Admin
  class TrainingDataExportsController < BaseController
    def index
      @training_data_exports, @pagination = paginate(TrainingDataExport.order(id: :desc))
    end

    def show
      @training_data_export = TrainingDataExport.find(params[:id])
    end
  end
end
