# frozen_string_literal: true

class ValidatePredictionJobContext < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :prediction_jobs, :context_id, algorithm: :concurrently
    validate_foreign_key :prediction_jobs, :contexts
  end
end
