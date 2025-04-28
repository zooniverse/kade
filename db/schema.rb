# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2025_04_27_195821) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "contexts", force: :cascade do |t|
    t.bigint "workflow_id", null: false
    t.bigint "project_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "active_subject_set_id", null: false
    t.bigint "pool_subject_set_id", null: false
    t.string "module_name"
    t.string "extractor_name"
    t.jsonb "metadata"
    t.index ["workflow_id", "project_id"], name: "index_contexts_on_workflow_id_and_project_id", unique: true
  end

  create_table "prediction_jobs", force: :cascade do |t|
    t.text "service_job_url", default: ""
    t.text "manifest_url", null: false
    t.string "state", null: false
    t.text "message", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "results_url", default: "", null: false
    t.bigint "subject_set_id", null: false
    t.float "probability_threshold", null: false
    t.float "randomisation_factor", null: false
  end

  create_table "predictions", force: :cascade do |t|
    t.bigint "subject_id", null: false
    t.text "image_url", null: false
    t.jsonb "results", default: {}, null: false
    t.string "user_id"
    t.string "agent_identifier"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_id"], name: "index_predictions_on_subject_id"
  end

  create_table "reductions", force: :cascade do |t|
    t.bigint "subject_id"
    t.bigint "workflow_id", null: false
    t.bigint "zooniverse_subject_id", null: false
    t.jsonb "labels", default: {}, null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "unique_id", null: false
    t.string "task_key", null: false
    t.index ["subject_id"], name: "index_reductions_on_subject_id"
    t.index ["workflow_id", "subject_id", "task_key"], name: "index_reductions_on_workflow_id_and_subject_id_and_task_key", unique: true
    t.index ["zooniverse_subject_id"], name: "index_reductions_on_zooniverse_subject_id"
  end

  create_table "subjects", force: :cascade do |t|
    t.bigint "zooniverse_subject_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "context_id", null: false
    t.jsonb "locations", default: []
    t.index ["zooniverse_subject_id", "context_id"], name: "index_subjects_on_zooniverse_subject_id_and_context_id", unique: true
  end

  create_table "training_data_exports", force: :cascade do |t|
    t.integer "state", default: 0, null: false
    t.bigint "workflow_id", null: false
    t.text "storage_path", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["id", "workflow_id", "state"], name: "index_training_data_exports_on_id_and_workflow_id_and_state", unique: true
  end

  create_table "training_jobs", force: :cascade do |t|
    t.text "service_job_url", default: ""
    t.text "manifest_url", null: false
    t.text "results_url", default: "", null: false
    t.string "state", null: false
    t.bigint "workflow_id", null: false
    t.text "message", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "subjects", "contexts"
end
