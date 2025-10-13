class DailylogsController < ApplicationController
  def index
    @dailylogs = Dailylog.page(params[:page]).per(25)
  rescue StandardError => e
    flash[:alert] = "Error connecting to PostgreSQL: #{e.message}"
    @dailylogs = Dailylog.page(1).per(25)
  end
end
