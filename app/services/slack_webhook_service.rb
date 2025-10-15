require 'net/http'
require 'json'

class SlackWebhookService
  attr_reader :webhook, :errors

  def initialize(slack_webhook)
    @webhook = slack_webhook
    @errors = []
  end

  def send_message(message_payload)
    return test_mode_response(message_payload) if webhook.test_mode?

    begin
      uri = URI(webhook.webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10
      http.open_timeout = 10

      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'
      request.body = message_payload.to_json

      response = http.request(request)

      handle_response(response)
    rescue Net::ReadTimeout, Net::OpenTimeout => e
      log_error("Timeout error: #{e.message}")
      { success: false, error: "Request timeout", code: nil }
    rescue StandardError => e
      log_error("Unexpected error: #{e.message}")
      { success: false, error: e.message, code: nil }
    end
  end

  def send_new_records_notification(new_records)
    return { success: false, error: "No records to notify" } if new_records.empty?
    return { success: false, error: "Webhook is not active" } unless webhook.active?
    return { success: false, error: "Rate limit - too soon since last trigger" } unless webhook.can_trigger?

    message = build_new_records_message(new_records)
    result = send_message(message)

    # Log the trigger
    log_trigger(new_records, result)

    # Update last triggered timestamp
    webhook.update(last_triggered_at: Time.current) if result[:success]

    # Check if we should deactivate due to failures
    webhook.deactivate_after_failures!

    result
  end

  private

  def build_new_records_message(records)
    count = records.count
    sample_records = records.limit(5)

    # Group by job site for better organization
    grouped_by_site = records.group(:jobsite).count

    {
      text: "New records detected in Data Lake",
      blocks: [
        {
          type: "header",
          text: {
            type: "plain_text",
            text: "New Records Alert",
            emoji: true
          }
        },
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "*#{count} new #{count == 1 ? 'record' : 'records'} detected*\n\n" \
                  "Process: `#{webhook.process}`\n" \
                  "Status: `#{webhook.status}`"
          }
        },
        {
          type: "divider"
        },
        {
          type: "section",
          fields: build_record_fields(sample_records)
        },
        grouped_by_site.any? ? build_site_summary(grouped_by_site) : nil,
        {
          type: "context",
          elements: [
            {
              type: "mrkdwn",
              text: "Data Lake updated: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
            }
          ]
        }
      ].compact
    }
  end

  def build_record_fields(records)
    fields = []

    # Add job IDs
    job_ids = records.pluck(:job_id).compact.uniq.first(5)
    if job_ids.any?
      fields << {
        type: "mrkdwn",
        text: "*Job IDs:*\n#{job_ids.map { |id| "• #{id}" }.join("\n")}"
      }
    end

    # Add sites
    sites = records.pluck(:site).compact.uniq.first(5)
    if sites.any?
      fields << {
        type: "mrkdwn",
        text: "*Sites:*\n#{sites.map { |site| "• #{site}" }.join("\n")}"
      }
    end

    fields
  end

  def build_site_summary(grouped_by_site)
    summary_text = grouped_by_site.map { |site, count|
      "• #{site || 'Unknown'}: #{count} #{count == 1 ? 'record' : 'records'}"
    }.first(10).join("\n")

    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: "*Distribution by Job Site:*\n#{summary_text}"
      }
    }
  end

  def test_mode_response(message_payload)
    Rails.logger.info "SlackWebhookService (TEST MODE): Would send message to #{webhook.name}"
    Rails.logger.info "Message payload: #{message_payload.to_json}"
    { success: true, error: nil, code: 200, test_mode: true }
  end

  def handle_response(response)
    case response.code.to_i
    when 200
      { success: true, error: nil, code: 200 }
    when 400
      { success: false, error: "Bad request - invalid payload", code: 400 }
    when 403
      { success: false, error: "Forbidden - invalid webhook URL", code: 403 }
    when 404
      { success: false, error: "Webhook URL not found", code: 404 }
    when 429
      { success: false, error: "Rate limited by Slack", code: 429 }
    when 500..599
      { success: false, error: "Slack server error", code: response.code.to_i }
    else
      { success: false, error: "Unexpected response: #{response.body}", code: response.code.to_i }
    end
  end

  def log_trigger(records, result)
    WebhookTriggerLog.create!(
      slack_webhook: webhook,
      dailylog_ids: records.pluck(:id),
      records_count: records.count,
      success: result[:success],
      response_code: result[:code],
      error_message: result[:error],
      triggered_at: Time.current
    )
  end

  def log_error(message)
    Rails.logger.error "SlackWebhookService Error (#{webhook.name}): #{message}"
    @errors << message
  end
end