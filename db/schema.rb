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

ActiveRecord::Schema[8.0].define(version: 2025_10_14_135256) do
  create_table "dailylogs", force: :cascade do |t|
    t.integer "job_id"
    t.integer "site_number"
    t.string "logtitle"
    t.text "notes"
    t.string "process"
    t.string "status"
    t.string "phase"
    t.string "jobsite"
    t.string "county"
    t.string "sector"
    t.string "site"
    t.string "permit"
    t.string "parcel"
    t.string "model_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_dailylogs_on_job_id"
    t.index ["jobsite"], name: "index_dailylogs_on_jobsite"
    t.index ["logtitle"], name: "index_dailylogs_on_logtitle"
    t.index ["site_number"], name: "index_dailylogs_on_site_number"
    t.index ["status"], name: "index_dailylogs_on_status"
  end

  create_table "sync_logs", force: :cascade do |t|
    t.string "table_name", null: false
    t.integer "records_synced", default: 0
    t.datetime "synced_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["synced_at"], name: "index_sync_logs_on_synced_at"
    t.index ["table_name"], name: "index_sync_logs_on_table_name"
  end
end
