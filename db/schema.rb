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

ActiveRecord::Schema[8.0].define(version: 2025_10_15_030147) do
  create_table "cleaning_logs", force: :cascade do |t|
    t.string "table_name", null: false
    t.integer "records_cleaned", default: 0
    t.integer "rules_applied", default: 0
    t.string "cleaning_version"
    t.datetime "cleaned_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cleaned_at"], name: "index_cleaning_logs_on_cleaned_at"
    t.index ["cleaning_version"], name: "index_cleaning_logs_on_cleaning_version"
    t.index ["table_name"], name: "index_cleaning_logs_on_table_name"
  end

  create_table "cleaning_rules", force: :cascade do |t|
    t.string "column_name", null: false
    t.string "original_value", null: false
    t.string "cleaned_value", null: false
    t.integer "status_category_id"
    t.boolean "active", default: true, null: false
    t.string "author"
    t.text "notes"
    t.integer "priority", default: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_cleaning_rules_on_active"
    t.index ["column_name", "original_value"], name: "index_cleaning_rules_on_column_and_value"
    t.index ["column_name", "original_value"], name: "index_cleaning_rules_unique", unique: true
    t.index ["priority"], name: "index_cleaning_rules_on_priority"
    t.index ["status_category_id"], name: "index_cleaning_rules_on_status_category_id"
  end

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
    t.text "addedby"
    t.text "cell"
    t.datetime "datecreated"
    t.datetime "dateonly"
    t.datetime "enddate"
    t.text "servicedate"
    t.datetime "startdate"
    t.text "sub"
    t.string "status_category", default: "nao_categorizado"
    t.index ["job_id"], name: "index_dailylogs_on_job_id"
    t.index ["jobsite"], name: "index_dailylogs_on_jobsite"
    t.index ["logtitle"], name: "index_dailylogs_on_logtitle"
    t.index ["site_number"], name: "index_dailylogs_on_site_number"
    t.index ["status"], name: "index_dailylogs_on_status"
    t.index ["status_category"], name: "index_dailylogs_on_status_category"
  end

  create_table "data_cleaning_rules", force: :cascade do |t|
    t.string "source_column", null: false
    t.string "source_value", null: false
    t.string "target_category", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_data_cleaning_rules_on_active"
    t.index ["source_column", "source_value"], name: "index_data_cleaning_rules_on_column_and_value", unique: true
    t.index ["source_column"], name: "index_data_cleaning_rules_on_source_column"
    t.index ["target_category"], name: "index_data_cleaning_rules_on_target_category"
  end

  create_table "slack_webhooks", force: :cascade do |t|
    t.string "name", null: false
    t.text "webhook_url", null: false
    t.string "process", null: false
    t.string "status", null: false
    t.boolean "active", default: true, null: false
    t.text "message_template"
    t.datetime "last_triggered_at"
    t.boolean "test_mode", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_slack_webhooks_on_active"
    t.index ["name"], name: "index_slack_webhooks_on_name", unique: true
    t.index ["process", "status"], name: "index_slack_webhooks_on_process_and_status"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "status_categories", force: :cascade do |t|
    t.string "name", null: false
    t.string "color", default: "#6c757d", null: false
    t.string "icon", default: "fa-circle"
    t.text "description"
    t.boolean "is_default", default: false
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_default"], name: "index_status_categories_on_is_default"
    t.index ["name"], name: "index_status_categories_on_name", unique: true
    t.index ["sort_order"], name: "index_status_categories_on_sort_order"
  end

  create_table "sync_logs", force: :cascade do |t|
    t.string "table_name", null: false
    t.integer "records_synced", default: 0
    t.datetime "synced_at", null: false
    t.integer "duration_ms"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "records_added", default: 0
    t.index ["synced_at"], name: "index_sync_logs_on_synced_at"
    t.index ["table_name"], name: "index_sync_logs_on_table_name"
  end

  create_table "webhook_trigger_logs", force: :cascade do |t|
    t.integer "slack_webhook_id", null: false
    t.text "dailylog_ids"
    t.integer "records_count", default: 0, null: false
    t.boolean "success", default: false, null: false
    t.integer "response_code"
    t.string "error_message"
    t.datetime "triggered_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slack_webhook_id"], name: "index_webhook_trigger_logs_on_slack_webhook_id"
    t.index ["success"], name: "index_webhook_trigger_logs_on_success"
    t.index ["triggered_at"], name: "index_webhook_trigger_logs_on_triggered_at"
  end

  add_foreign_key "cleaning_rules", "status_categories"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "webhook_trigger_logs", "slack_webhooks"
end
