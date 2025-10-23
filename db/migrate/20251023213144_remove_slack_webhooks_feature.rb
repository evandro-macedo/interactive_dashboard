class RemoveSlackWebhooksFeature < ActiveRecord::Migration[8.0]
  def change
    # Drop webhook-related tables (obsolete feature)
    drop_table :webhook_trigger_logs, if_exists: true do |t|
      t.integer :slack_webhook_id, null: false
      t.text :dailylog_ids
      t.integer :records_count, default: 0, null: false
      t.boolean :success, default: false, null: false
      t.integer :response_code
      t.string :error_message
      t.datetime :triggered_at, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index :slack_webhook_id
      t.index :success
      t.index :triggered_at
    end

    drop_table :slack_webhooks, if_exists: true do |t|
      t.string :name, null: false
      t.text :webhook_url, null: false
      t.string :process, null: false
      t.string :status, null: false
      t.boolean :active, default: true, null: false
      t.text :message_template
      t.datetime :last_triggered_at
      t.boolean :test_mode, default: false, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index :active
      t.index :name, unique: true
      t.index [:process, :status]
    end
  end
end
