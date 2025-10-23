class ConstructionOverviewController < ApplicationController
  def index
    # Basic data for initial page load
    @last_sync = Dailylog.last_sync_info
    @total_records = Dailylog.count
  end
end
