class PostgresSourceDailylogFmea < PostgresSourceRecord
  self.table_name = "dailylogs_fmea"

  # Disable timestamps if the external table doesn't have them
  self.record_timestamps = false

  # Scopes úteis para Query 10
  scope :with_fmea, -> { where("failure_group ILIKE ?", "%fmea%") }
  scope :not_report_true, -> { where(not_report: true) }
  scope :checklist_done_status, -> { where(status: "checklist done") }
  scope :rework_requested_status, -> { where(status: "rework requested") }
end
