class DailylogFmea < ApplicationRecord
  # Agora herda de ApplicationRecord (banco SQLite local)
  self.table_name = "dailylogs_fmea"

  # Associação com dailylogs (opcional, pois job_id pode não existir sempre)
  belongs_to :dailylog, foreign_key: :job_id, primary_key: :job_id, optional: true

  # Security: Whitelist of searchable columns with metadata
  SEARCHABLE_COLUMNS = {
    'all' => { label: 'All Columns', group: nil },
    'job_id' => { label: 'Job ID', group: 'IDs', numeric: true },
    'process' => { label: 'Process', group: 'Information' },
    'status' => { label: 'Status', group: 'Information' },
    'phase' => { label: 'Phase', group: 'Information' },
    'failure_group' => { label: 'Failure Group', group: 'FMEA' },
    'failure_item' => { label: 'Failure Item', group: 'FMEA' },
    'addedby' => { label: 'Added By', group: 'Information' },
    'logtitle' => { label: 'Log Title', group: 'Information' },
    'notes' => { label: 'Notes', group: 'Information' },
    'jobsite' => { label: 'Job Site', group: 'Location' },
    'county' => { label: 'County', group: 'Location' },
    'sector' => { label: 'Sector', group: 'Location' }
  }.freeze

  # Dynamic search scope with column selection
  scope :search_in_column, ->(query, column = 'all') {
    return all if query.blank?

    # Security: Only allow whitelisted columns
    return all unless SEARCHABLE_COLUMNS.key?(column)

    if column == 'all'
      # Global search across key columns (adapted for SQLite)
      where(
        "CAST(job_id AS TEXT) LIKE :q OR
         process LIKE :q OR
         status LIKE :q OR
         phase LIKE :q OR
         failure_group LIKE :q OR
         failure_item LIKE :q OR
         addedby LIKE :q OR
         logtitle LIKE :q OR
         notes LIKE :q OR
         jobsite LIKE :q OR
         county LIKE :q OR
         sector LIKE :q",
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

  # Multi-filter scope: Allows combining multiple column filters (AND conditions)
  # Usage: DailylogFmea.multi_filter({ 'job_id' => '596', 'process' => 'framing' })
  # Security: Only whitelisted columns are allowed
  scope :multi_filter, ->(filters = {}) {
    relation = all

    return relation if filters.blank?

    filters.each do |column, value|
      next if value.blank?

      # Security: Only allow whitelisted columns
      next unless SEARCHABLE_COLUMNS.key?(column.to_s)

      column_str = column.to_s
      column_config = SEARCHABLE_COLUMNS[column_str]

      if column_config[:numeric]
        relation = relation.where("CAST(#{column_str} AS TEXT) LIKE ?", "%#{sanitize_sql_like(value)}%")
      else
        relation = relation.where("#{column_str} LIKE ?", "%#{sanitize_sql_like(value)}%")
      end
    end

    relation
  }

  # Helper: Group columns by category for dropdown
  def self.grouped_searchable_columns
    SEARCHABLE_COLUMNS.group_by { |_, config| config[:group] }
  end

  # Scopes úteis para Query 10 do firefighting
  # REGRA 0: Processos marcados como not_report = TRUE
  scope :not_report_true, -> { where(not_report: true) }

  # REGRA 2: Checklist done com FMEA
  scope :with_fmea, -> { where("failure_group LIKE ?", "%fmea%") }
  scope :checklist_done_status, -> { where(status: "checklist done") }

  # REGRA 3: Rework requested com FMEA
  scope :rework_requested_status, -> { where(status: "rework requested") }

  # Scope para buscar por job_id e process
  scope :for_job_and_process, ->(job_id, process) {
    where(job_id: job_id, process: process)
  }

  # Helper: Info da última sincronização
  def self.last_sync_info
    SyncLog.where(table_name: "dailylogs_fmea")
           .order(synced_at: :desc)
           .first
  end

  # Helper: Verificar se processo não precisa de report (Query 10 Rule 0)
  def self.process_not_report?(process, status)
    exists?(process: process, status: status, not_report: true)
  end
end
