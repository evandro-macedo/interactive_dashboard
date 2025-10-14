class AddRecordsAddedToSyncLogs < ActiveRecord::Migration[8.0]
  def change
    add_column :sync_logs, :records_added, :integer, default: 0
  end
end
