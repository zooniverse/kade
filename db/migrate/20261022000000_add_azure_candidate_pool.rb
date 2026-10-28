# frozen_string_literal: true

class AddAzureCandidatePool < ActiveRecord::Migration[7.0]
  def change
    add_column :contexts, :prediction_source, :string, null: false, default: 'panoptes_subject_set'
    change_column_null :contexts, :pool_subject_set_id, true

    create_table :candidate_subjects do |t|
      t.references :context, null: false, foreign_key: true
      t.string :external_id, null: false
      t.jsonb :metadata, null: false, default: {}
      t.jsonb :locations, null: false, default: []
      t.bigint :zooniverse_subject_id
      t.datetime :registration_started_at
      t.timestamps
    end
    add_index :candidate_subjects, %i[context_id external_id], unique: true

    add_column :prediction_jobs, :context_id, :bigint
    add_foreign_key :prediction_jobs, :contexts, validate: false
    add_column :prediction_jobs, :catalogue_snapshot, :jsonb
    add_column :prediction_jobs, :selection, :jsonb
    add_column :prediction_jobs, :applied_at, :datetime
  end
end
