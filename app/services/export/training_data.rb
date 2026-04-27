# frozen_string_literal: true

module Export
  class TrainingData
    attr_reader :training_data_export

    def initialize(training_data_export)
      @training_data_export = training_data_export
    end

    def run
      context = Context.find_by(workflow_id: training_data_export.workflow_id)
      csv_export_file = Format::TrainingDataCsv.new(
        training_data_export.workflow_id,
        LabelExtractors::Registry.label_column_headers(context.module_name, context.extractor_name)
      ).run

      # upload the export file via active storage
      # ensure we specify a known key here so we know the location on contianer storage
      # vs a rails generated key id
      training_data_export.file.attach(
        key: training_data_export.storage_path_key,
        io: csv_export_file,
        filename: training_data_export.storage_path_file_name
      )

      # finally mark the export model state change
      if training_data_export.file.attached?
        training_data_export.finished!
      else
        training_data_export.failed!
      end
    end
  end
end
