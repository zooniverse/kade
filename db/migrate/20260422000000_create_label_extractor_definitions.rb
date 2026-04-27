# frozen_string_literal: true

class CreateLabelExtractorDefinitions < ActiveRecord::Migration[7.0]
  def change
    create_table :label_extractor_definitions do |t|
      t.string :module_name, null: false
      t.string :extractor_name, null: false
      t.boolean :enabled, null: false, default: true
      t.jsonb :config, null: false, default: {}

      t.timestamps
    end

    add_index(
      :label_extractor_definitions,
      %i[module_name extractor_name],
      unique: true,
      name: 'index_label_extractor_definitions_on_module_and_extractor'
    )
  end
end
