class DailylogsController < ApplicationController
  # Whitelist of sortable columns for security
  SORTABLE_COLUMNS = %w[
    id job_id site_number logtitle notes process status phase jobsite
    county sector site permit parcel model_code
    addedby cell datecreated dateonly enddate servicedate startdate sub
    created_at updated_at
  ].freeze

  def index
    # Data Layer Consistency: Use same scope for initial render and turbo updates
    # Security: search_in_column validates column against whitelist
    @dailylogs = Dailylog.search_in_column(params[:q], params[:column])
                         .then { |relation| apply_sorting(relation) }
                         .page(params[:page])
                         .per(25)

    respond_to do |format|
      format.html # Regular page load
      format.turbo_stream {
        # ✅ Use UPDATE not REPLACE (lessons-learned pattern)
        # Preserves wrapper and allows consecutive updates
        render turbo_stream: turbo_stream.update(
          "dailylogs_table",
          partial: "table",
          locals: { dailylogs: @dailylogs }
        )
      }
    end
  rescue StandardError => e
    flash[:alert] = "Error connecting to PostgreSQL: #{e.message}"
    @dailylogs = Dailylog.page(1).per(25)
  end

  private

  def apply_sorting(relation)
    sort_column = params[:sort].presence
    sort_direction = params[:direction].presence

    # Security: Only allow whitelisted columns
    return relation unless SORTABLE_COLUMNS.include?(sort_column)

    # Validate direction
    direction = %w[asc desc].include?(sort_direction) ? sort_direction : "asc"

    relation.order("#{sort_column} #{direction}")
  end
end
