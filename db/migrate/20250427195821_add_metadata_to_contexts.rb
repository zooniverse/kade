class AddMetadataToContexts < ActiveRecord::Migration[7.0]
  def change
    add_column :contexts, :metadata, :jsonb
  end
end
