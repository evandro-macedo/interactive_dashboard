class Dailylog < PostgresSourceRecord
  self.table_name = "dailylogs"

  # Disable timestamps if the external table doesn't have them
  # Remove these lines if the table has created_at/updated_at columns
  self.record_timestamps = false

  # Security: Whitelist of searchable columns with metadata
  SEARCHABLE_COLUMNS = {
    'all' => { label: 'All Columns', group: nil },
    'job_id' => { label: 'Job ID', group: 'IDs', numeric: true },
    'site_number' => { label: 'Site Number', group: 'IDs', numeric: true },
    'logtitle' => { label: 'Log Title', group: 'Information' },
    'notes' => { label: 'Notes', group: 'Information' },
    'process' => { label: 'Process', group: 'Information' },
    'status' => { label: 'Status', group: 'Information' },
    'phase' => { label: 'Phase', group: 'Information' },
    'jobsite' => { label: 'Job Site', group: 'Location' },
    'county' => { label: 'County', group: 'Location' },
    'sector' => { label: 'Sector', group: 'Location' },
    'site' => { label: 'Site', group: 'Location' },
    'permit' => { label: 'Permit', group: 'Documents' },
    'parcel' => { label: 'Parcel', group: 'Documents' },
    'model_code' => { label: 'Model Code', group: 'Documents' }
  }.freeze

  # Dynamic search scope with column selection
  # Data Layer Consistency: Use this same scope everywhere (lessons-learned pattern)
  scope :search_in_column, ->(query, column = 'all') {
    return all if query.blank?

    # Security: Only allow whitelisted columns
    return all unless SEARCHABLE_COLUMNS.key?(column)

    if column == 'all'
      # Global search across key columns
      where(
        "job_id::text ILIKE :q OR
         site_number::text ILIKE :q OR
         logtitle ILIKE :q OR
         notes ILIKE :q OR
         process ILIKE :q OR
         status ILIKE :q OR
         jobsite ILIKE :q OR
         county ILIKE :q OR
         permit ILIKE :q OR
         parcel ILIKE :q",
        q: "%#{sanitize_sql_like(query)}%"
      )
    else
      # Specific column search
      column_config = SEARCHABLE_COLUMNS[column]

      if column_config[:numeric]
        where("#{column}::text ILIKE ?", "%#{sanitize_sql_like(query)}%")
      else
        where("#{column} ILIKE ?", "%#{sanitize_sql_like(query)}%")
      end
    end
  }

  # Helper: Group columns by category for dropdown
  def self.grouped_searchable_columns
    SEARCHABLE_COLUMNS.group_by { |_, config| config[:group] }
  end
end
