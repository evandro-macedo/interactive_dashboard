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

  # FMEA table columns
  FMEA_SORTABLE_COLUMNS = %w[
    id job_id process status phase failure_group failure_item
    is_multitag not_report checklist_done fees datecreated
    addedby logtitle notes county sector cell jobsite site
    site_number permit parcel model_code
    created_at updated_at
  ].freeze

  FMEA_VISIBLE_COLUMNS = %w[
    id
    job_id
    process
    status
    phase
    failure_group
    failure_item
    not_report
    datecreated
    addedby
  ].freeze

  def index
    # Multi-filter support: params[:filters] contains hash of column => value
    # Backward compatibility: Falls back to params[:q] and params[:column]
    @per_page = 50
    @offset = params[:offset]&.to_i || 0
    @fmea_offset = params[:fmea_offset]&.to_i || 0

    # Parse filters for dailylogs table
    filters = parse_filters(params[:filters])
    @active_filters = filters

    # Apply filters using new multi_filter scope or legacy search_in_column
    @dailylogs = if filters.present?
                   Dailylog.multi_filter(filters)
                 else
                   Dailylog.search_in_column(params[:q], params[:column])
                 end
                 .then { |relation| apply_sorting(relation) }
                 .limit(@per_page + 1)
                 .offset(@offset)

    @has_more = @dailylogs.size > @per_page
    @dailylogs = @dailylogs.first(@per_page) if @has_more

    # Parse filters for FMEA table
    fmea_filters = parse_filters(params[:fmea_filters])
    @active_fmea_filters = fmea_filters

    # FMEA table (separate search and filtering)
    @dailylogs_fmea = if fmea_filters.present?
                        DailylogFmea.multi_filter(fmea_filters)
                      else
                        DailylogFmea.search_in_column(params[:fmea_q], params[:fmea_column])
                      end
                      .then { |relation| apply_fmea_sorting(relation) }
                      .limit(@per_page + 1)
                      .offset(@fmea_offset)

    @has_more_fmea = @dailylogs_fmea.size > @per_page
    @dailylogs_fmea = @dailylogs_fmea.first(@per_page) if @has_more_fmea

    # Turbo Frame Navigation Pattern:
    # Links with data-turbo-frame automatically extract the matching frame from HTML response
    # No need for explicit format.turbo_stream - Turbo handles it automatically
  rescue StandardError => e
    flash[:alert] = "Error connecting to data lake: #{e.message}"
    @dailylogs = Dailylog.limit(50)
    @dailylogs_fmea = DailylogFmea.limit(50)
    @has_more = false
    @has_more_fmea = false
    @active_filters = {}
    @active_fmea_filters = {}
  end

  private

  def parse_filters(filters_param)
    return {} if filters_param.blank?

    # Filters can come as a hash from forms or URL params
    # Security: Only allow whitelisted columns
    # Convert ActionController::Parameters to hash safely
    hash = filters_param.respond_to?(:to_unsafe_h) ? filters_param.to_unsafe_h : filters_param.to_h

    hash.select do |column, value|
      value.present? && (Dailylog::SEARCHABLE_COLUMNS.key?(column.to_s) || DailylogFmea::SEARCHABLE_COLUMNS.key?(column.to_s))
    end
  end

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

  def apply_fmea_sorting(relation)
    sort_column = params[:fmea_sort].presence
    sort_direction = params[:fmea_direction].presence

    # Default sort: datecreated DESC (most recent first)
    if sort_column.blank?
      return relation.order(datecreated: :desc)
    end

    # Security: Only allow whitelisted columns
    return relation.order(datecreated: :desc) unless FMEA_SORTABLE_COLUMNS.include?(sort_column)

    # Validate direction
    direction = %w[asc desc].include?(sort_direction) ? sort_direction : "asc"

    relation.order("#{sort_column} #{direction}")
  end
end
