class WebhookTriggerLog < ApplicationRecord
  # Associations
  belongs_to :slack_webhook

  # Validations
  validates :triggered_at, presence: true
  validates :records_count, numericality: { greater_than_or_equal_to: 0 }

  # Serialization for dailylog_ids array
  serialize :dailylog_ids, coder: JSON, type: Array

  # Scopes
  scope :recent, -> { order(triggered_at: :desc) }
  scope :successful, -> { where(success: true) }
  scope :failed, -> { where(success: false) }
  scope :today, -> { where('triggered_at >= ?', Time.current.beginning_of_day) }
  scope :this_week, -> { where('triggered_at >= ?', 1.week.ago) }
  scope :this_month, -> { where('triggered_at >= ?', 1.month.ago) }

  # Class methods for statistics
  def self.success_rate
    total = count
    return 0 if total == 0
    (successful.count.to_f / total * 100).round(2)
  end

  def self.daily_stats(days = 7)
    start_date = days.days.ago.beginning_of_day
    where('triggered_at >= ?', start_date)
      .group('DATE(triggered_at)')
      .group(:success)
      .count
  end

  # Instance methods
  def status_badge
    success? ? 'success' : 'danger'
  end

  def status_text
    success? ? 'Success' : 'Failed'
  end

  def dailylogs
    return [] if dailylog_ids.blank?
    Dailylog.where(id: dailylog_ids)
  end

  def duration_ms
    # If we want to track execution time in the future
    nil
  end

  def response_status
    if response_code.present?
      "#{response_code} - #{http_status_text}"
    else
      'N/A'
    end
  end

  def message_preview
    if success?
      "Successfully notified #{records_count} new #{'record'.pluralize(records_count)}"
    else
      error_message.presence || 'Unknown error'
    end
  end

  private

  def http_status_text
    case response_code
    when 200 then 'OK'
    when 201 then 'Created'
    when 204 then 'No Content'
    when 400 then 'Bad Request'
    when 401 then 'Unauthorized'
    when 403 then 'Forbidden'
    when 404 then 'Not Found'
    when 422 then 'Unprocessable Entity'
    when 429 then 'Too Many Requests'
    when 500 then 'Internal Server Error'
    when 502 then 'Bad Gateway'
    when 503 then 'Service Unavailable'
    when 504 then 'Gateway Timeout'
    else 'Unknown'
    end
  end
end