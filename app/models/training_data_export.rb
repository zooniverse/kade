# frozen_string_literal: true

class TrainingDataExport < ApplicationRecord
  # default is started via the migration default: 0
  enum :state, %i[started finished failed]

  validates :state, :workflow_id, presence: true

  has_one_attached :file

  # path key used in the active storage has_one file association
  # however we need to remove the stored container path prefix
  # to ensure we upload the file to the correct container location path
  def storage_path_key
    storage_path.delete_prefix("/#{Zoobot::Storage.container_name}")
  end

  # the name of the file for the uploaded blob
  def storage_path_file_name
    File.basename(storage_path)
  end
end
