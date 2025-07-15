class AddLastCompletionRateToContexts < ActiveRecord::Migration[7.0]
  def change
    add_column :contexts, :last_completion_rate, :float, default: 0.0
  end
end
