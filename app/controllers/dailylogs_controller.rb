class DailylogsController < ApplicationController
  # Whitelist of sortable columns for security
  SORTABLE_COLUMNS = %w[
    id job_id site_number logtitle notes process status phase jobsite
    county sector site permit parcel model_code
    addedby cell datecreated dateonly enddate servicedate startdate sub
    created_at updated_at
  ].freeze

  # Visible columns in display order (priority columns first)
  VISIBLE_COLUMNS = %w[
    id
    job_id
    process
    status
    addedby
    datecreated
    servicedate
    logtitle
    phase
    county
    sub
    site_number
    notes
    jobsite
    sector
    site
    permit
    parcel
    cell
    dateonly
    enddate
    startdate
    status_category
  ].freeze

  def index
    # Data Layer Consistency: Use same scope for initial render and turbo updates
    # Security: search_in_column validates column against whitelist
    @dailylogs = Dailylog.search_in_column(params[:q], params[:column])
                         .then { |relation| apply_sorting(relation) }
                         .page(params[:page])
                         .per(25)

    # Turbo Frame Navigation Pattern:
    # Links with data-turbo-frame automatically extract the matching frame from HTML response
    # No need for explicit format.turbo_stream - Turbo handles it automatically
  rescue StandardError => e
    flash[:alert] = "Error connecting to PostgreSQL: #{e.message}"
    @dailylogs = Dailylog.page(1).per(25)
  end

  private

  def apply_sorting(relation)
    sort_column = params[:sort].presence
    sort_direction = params[:direction].presence

    # Default sort: datecreated DESC (most recent first)
    if sort_column.blank?
      return relation.order(datecreated: :desc)
    end

    # Security: Only allow whitelisted columns
    return relation.order(datecreated: :desc) unless SORTABLE_COLUMNS.include?(sort_column)

    # Validate direction
    direction = %w[asc desc].include?(sort_direction) ? sort_direction : "asc"

    relation.order("#{sort_column} #{direction}")
  end
end
