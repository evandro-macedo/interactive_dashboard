class SlackWebhook < ApplicationRecord
  # Associations
  has_many :webhook_trigger_logs, dependent: :destroy

  # Encrypts webhook_url for security
  # NOTE: Temporarily disabled until encryption keys are properly configured
  # encrypts :webhook_url

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :webhook_url, presence: true
  validates :process, presence: true
  validates :status, presence: true

  # Custom validation for Slack webhook URL
  validate :valid_slack_webhook_url

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_process_and_status, ->(process, status) {
    active.where(process: process, status: status)
  }

  # Instance methods
  def trigger_count
    webhook_trigger_logs.count
  end

  def successful_triggers
    webhook_trigger_logs.where(success: true).count
  end

  def failed_triggers
    webhook_trigger_logs.where(success: false).count
  end

  def success_rate
    return 0 if trigger_count == 0
    (successful_triggers.to_f / trigger_count * 100).round(2)
  end

  def last_trigger
    webhook_trigger_logs.order(triggered_at: :desc).first
  end

  def can_trigger?
    return false unless active?

    # Rate limiting: Allow only one trigger per 5 minutes
    if last_triggered_at.present?
      Time.current - last_triggered_at > 5.minutes
    else
      true
    end
  end

  def deactivate_after_failures!
    recent_failures = webhook_trigger_logs
      .where('triggered_at > ?', 24.hours.ago)
      .where(success: false)
      .count

    if recent_failures >= 5
      update!(active: false)
      Rails.logger.warn "Slack webhook '#{name}' deactivated after #{recent_failures} failures"
      true
    else
      false
    end
  end

  private

  def valid_slack_webhook_url
    return if webhook_url.blank?

    # Validate that it's a valid Slack webhook URL
    # Format: https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX
    unless webhook_url.match?(/\Ahttps:\/\/hooks\.slack\.com\/services\/[A-Za-z0-9\/]+\z/)
      errors.add(:webhook_url, 'must be a valid Slack webhook URL (https://hooks.slack.com/services/...)')
    end
  end
end