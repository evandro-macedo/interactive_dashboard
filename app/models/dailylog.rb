class Dailylog < ApplicationRecord
  # Agora herda de ApplicationRecord (banco SQLite local)

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
    'addedby' => { label: 'Added By', group: 'Information' },
    'cell' => { label: 'Cell', group: 'Information' },
    'sub' => { label: 'Sub', group: 'Information' },
    'jobsite' => { label: 'Job Site', group: 'Location' },
    'county' => { label: 'County', group: 'Location' },
    'sector' => { label: 'Sector', group: 'Location' },
    'site' => { label: 'Site', group: 'Location' },
    'permit' => { label: 'Permit', group: 'Documents' },
    'parcel' => { label: 'Parcel', group: 'Documents' },
    'model_code' => { label: 'Model Code', group: 'Documents' },
    'servicedate' => { label: 'Service Date', group: 'Dates' },
    'datecreated' => { label: 'Date Created', group: 'Dates' },
    'dateonly' => { label: 'Date Only', group: 'Dates' },
    'startdate' => { label: 'Start Date', group: 'Dates' },
    'enddate' => { label: 'End Date', group: 'Dates' }
  }.freeze

  # Dynamic search scope with column selection
  # Data Layer Consistency: Use this same scope everywhere (lessons-learned pattern)
  scope :search_in_column, ->(query, column = 'all') {
    return all if query.blank?

    # Security: Only allow whitelisted columns
    return all unless SEARCHABLE_COLUMNS.key?(column)

    if column == 'all'
      # Global search across key columns (adapted for SQLite)
      where(
        "CAST(job_id AS TEXT) LIKE :q OR
         CAST(site_number AS TEXT) LIKE :q OR
         logtitle LIKE :q OR
         notes LIKE :q OR
         process LIKE :q OR
         status LIKE :q OR
         phase LIKE :q OR
         addedby LIKE :q OR
         cell LIKE :q OR
         sub LIKE :q OR
         jobsite LIKE :q OR
         county LIKE :q OR
         sector LIKE :q OR
         site LIKE :q OR
         permit LIKE :q OR
         parcel LIKE :q OR
         model_code LIKE :q OR
         servicedate LIKE :q OR
         CAST(datecreated AS TEXT) LIKE :q OR
         CAST(dateonly AS TEXT) LIKE :q OR
         CAST(startdate AS TEXT) LIKE :q OR
         CAST(enddate AS TEXT) LIKE :q",
        q: "%#{sanitize_sql_like(query)}%"
      )
    else
      # Specific column search
      column_config = SEARCHABLE_COLUMNS[column]

      if column_config[:numeric]
        where("CAST(#{column} AS TEXT) LIKE ?", "%#{sanitize_sql_like(query)}%")
      else
        where("#{column} LIKE ?", "%#{sanitize_sql_like(query)}%")
      end
    end
  }

  # Helper: Group columns by category for dropdown
  def self.grouped_searchable_columns
    SEARCHABLE_COLUMNS.group_by { |_, config| config[:group] }
  end

  # Helper: Info da última sincronização
  def self.last_sync_info
    SyncLog.where(table_name: 'dailylogs')
           .order(synced_at: :desc)
           .first
  end
end
