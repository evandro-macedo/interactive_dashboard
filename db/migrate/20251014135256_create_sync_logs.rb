class CreateSyncLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :sync_logs do |t|
      t.string :table_name, null: false
      t.integer :records_synced, default: 0
      t.datetime :synced_at, null: false
      t.integer :duration_ms
      t.text :error_message

      t.timestamps
    end

    add_index :sync_logs, :table_name
    add_index :sync_logs, :synced_at
  end
end
