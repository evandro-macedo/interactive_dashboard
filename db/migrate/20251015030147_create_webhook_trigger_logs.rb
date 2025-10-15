class CreateWebhookTriggerLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_trigger_logs do |t|
      t.references :slack_webhook, null: false, foreign_key: true
      t.text :dailylog_ids
      t.integer :records_count, null: false, default: 0
      t.boolean :success, null: false, default: false
      t.integer :response_code
      t.string :error_message
      t.datetime :triggered_at, null: false

      t.timestamps
    end

    # Add indexes for performance
    add_index :webhook_trigger_logs, :triggered_at
    add_index :webhook_trigger_logs, :success
  end
end
