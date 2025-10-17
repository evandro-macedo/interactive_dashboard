class ConstructionOverviewController < ApplicationController
  def index
    # Filter records from the last month
    one_month_ago = 1.month.ago

    # Use .count which returns a Hash: {"phase" => count}
    stats_hash = Dailylog
      .where("datecreated >= ?", one_month_ago)
      .group(:phase)
      .count

    # Sort by count descending - returns array of [phase, count]
    @stats_by_phase = stats_hash.sort_by { |_, count| -count }
    @total_records = stats_hash.values.sum
    @last_sync = Dailylog.last_sync_info
  end
end
