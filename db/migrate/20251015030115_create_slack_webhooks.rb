class CreateSlackWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :slack_webhooks do |t|
      t.string :name, null: false
      t.text :webhook_url, null: false
      t.string :process, null: false
      t.string :status, null: false
      t.boolean :active, default: true, null: false
      t.text :message_template
      t.datetime :last_triggered_at
      t.boolean :test_mode, default: false, null: false

      t.timestamps
    end

    # Add indexes for performance
    add_index :slack_webhooks, [:process, :status]
    add_index :slack_webhooks, :active
    add_index :slack_webhooks, :name, unique: true
  end
end
