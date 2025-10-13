class Dailylog < PostgresSourceRecord
  self.table_name = "dailylogs"

  # Disable timestamps if the external table doesn't have them
  # Remove these lines if the table has created_at/updated_at columns
  self.record_timestamps = false
end
