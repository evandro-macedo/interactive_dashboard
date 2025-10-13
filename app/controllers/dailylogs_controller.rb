class DailylogsController < ApplicationController
  def index
    # Data Layer Consistency: Use same scope for initial render and turbo updates
    # Security: search_in_column validates column against whitelist
    @dailylogs = Dailylog.search_in_column(params[:q], params[:column])
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
end
