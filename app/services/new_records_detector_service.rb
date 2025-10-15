class NewRecordsDetectorService
  attr_reader :new_records, :notifications_sent

  def initialize(new_records)
    @new_records = new_records
    @notifications_sent = []
  end

  def process_webhooks
    return if new_records.empty?

    Rails.logger.info "NewRecordsDetectorService: Processing #{new_records.count} new records"

    # Group new records by process and status
    grouped_records = group_records_by_trigger

    # Find matching webhooks for each group
    grouped_records.each do |trigger_key, records|
      process = trigger_key[:process]
      status = trigger_key[:status]

      # Skip if process or status is nil/blank
      next if process.blank? || status.blank?

      # Find active webhooks for this combination
      webhooks = SlackWebhook.for_process_and_status(process, status)

      Rails.logger.info "Found #{webhooks.count} webhooks for process: '#{process}', status: '#{status}'"

      # Send notification for each webhook
      webhooks.each do |webhook|
        send_notification(webhook, records)
      end
    end

    log_summary
  end

  private

  def group_records_by_trigger
    grouped = {}

    new_records.find_each do |record|
      key = { process: record.process, status: record.status }
      grouped[key] ||= []
      grouped[key] << record.id
    end

    # Convert arrays of IDs back to ActiveRecord relations
    grouped.transform_values do |record_ids|
      Dailylog.where(id: record_ids)
    end
  end

  def send_notification(webhook, records)
    Rails.logger.info "Sending notification to webhook '#{webhook.name}' for #{records.count} records"

    # Queue the notification job
    SlackNotificationJob.perform_later(webhook.id, records.pluck(:id))

    @notifications_sent << {
      webhook: webhook.name,
      records_count: records.count,
      process: webhook.process,
      status: webhook.status
    }
  rescue StandardError => e
    Rails.logger.error "Failed to queue notification for webhook '#{webhook.name}': #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def log_summary
    if @notifications_sent.any?
      Rails.logger.info "NewRecordsDetectorService Summary:"
      Rails.logger.info "- Total new records: #{new_records.count}"
      Rails.logger.info "- Notifications queued: #{@notifications_sent.count}"

      @notifications_sent.each do |notification|
        Rails.logger.info "  • #{notification[:webhook]}: #{notification[:records_count]} records " \
                          "(#{notification[:process]} / #{notification[:status]})"
      end
    else
      Rails.logger.info "NewRecordsDetectorService: No matching webhooks found for new records"
    end
  end
end