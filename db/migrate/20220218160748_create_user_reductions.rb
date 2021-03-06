class CreateUserReductions < ActiveRecord::Migration[7.0]
  def change
    create_table :user_reductions do |t|
      t.belongs_to :subject, index: true
      t.bigint     :workflow_id, null: false
      t.bigint     :zooniverse_subject_id, null: false, index: true
      t.jsonb      :labels, null: false, default: {}
      t.jsonb      :raw_payload, null: false, default: {}
      t.index      %i[workflow_id subject_id], unique: true

      t.timestamps
    end
  end
end
