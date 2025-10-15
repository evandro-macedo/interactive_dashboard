class SlackNotificationJob < ApplicationJob
  queue_as :default

  # Retry configuration
  retry_on Net::ReadTimeout, Net::OpenTimeout, wait: :polynomially_longer, attempts: 3
  retry_on StandardError, wait: 5.seconds, attempts: 2

  def perform(webhook_id, dailylog_ids)
    webhook = SlackWebhook.find(webhook_id)
    records = Dailylog.where(id: dailylog_ids)

    # Skip if webhook is no longer active
    unless webhook.active?
      Rails.logger.info "SlackNotificationJob: Webhook '#{webhook.name}' is inactive, skipping notification"
      return
    end

    # Skip if no records found
    if records.empty?
      Rails.logger.warn "SlackNotificationJob: No records found for IDs #{dailylog_ids.inspect}"
      return
    end

    Rails.logger.info "SlackNotificationJob: Sending notification for webhook '#{webhook.name}' with #{records.count} records"

    # Send notification using the service
    service = SlackWebhookService.new(webhook)
    result = service.send_new_records_notification(records)

    if result[:success]
      Rails.logger.info "SlackNotificationJob: Successfully sent notification to '#{webhook.name}'"
    else
      Rails.logger.error "SlackNotificationJob: Failed to send notification to '#{webhook.name}': #{result[:error]}"

      # Re-raise error for retry mechanism if it's a temporary failure
      if result[:code].in?([429, 500, 502, 503, 504])
        raise "Temporary Slack error (#{result[:code]}): #{result[:error]}"
      end
    end

    result
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "SlackNotificationJob: Webhook not found (ID: #{webhook_id})"
    raise e
  rescue StandardError => e
    Rails.logger.error "SlackNotificationJob: Unexpected error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end