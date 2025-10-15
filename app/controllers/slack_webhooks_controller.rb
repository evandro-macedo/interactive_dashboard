class SlackWebhooksController < ApplicationController
  before_action :set_slack_webhook, only: [:show, :edit, :update, :destroy, :test_webhook, :toggle_active]

  def index
    @slack_webhooks = SlackWebhook.includes(:webhook_trigger_logs)
                                  .order(created_at: :desc)

    # Get unique process and status values for filters
    @available_processes = Dailylog.distinct.pluck(:process).compact.sort
    @available_statuses = Dailylog.distinct.pluck(:status).compact.sort
  end

  def show
    @recent_logs = @slack_webhook.webhook_trigger_logs
                                 .includes(:slack_webhook)
                                 .recent
                                 .limit(20)
  end

  def new
    @slack_webhook = SlackWebhook.new
    @available_processes = Dailylog.distinct.pluck(:process).compact.sort
    @available_statuses = Dailylog.distinct.pluck(:status).compact.sort
  end

  def create
    @slack_webhook = SlackWebhook.new(slack_webhook_params)

    if @slack_webhook.save
      redirect_to slack_webhooks_path, notice: 'Slack webhook was successfully created.'
    else
      @available_processes = Dailylog.distinct.pluck(:process).compact.sort
      @available_statuses = Dailylog.distinct.pluck(:status).compact.sort
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @available_processes = Dailylog.distinct.pluck(:process).compact.sort
    @available_statuses = Dailylog.distinct.pluck(:status).compact.sort
  end

  def update
    if @slack_webhook.update(slack_webhook_params)
      redirect_to slack_webhooks_path, notice: 'Slack webhook was successfully updated.'
    else
      @available_processes = Dailylog.distinct.pluck(:process).compact.sort
      @available_statuses = Dailylog.distinct.pluck(:status).compact.sort
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @slack_webhook.destroy!
    redirect_to slack_webhooks_path, notice: 'Slack webhook was successfully deleted.'
  end

  def test_webhook
    service = SlackWebhookService.new(@slack_webhook)

    # Create test data
    test_message = {
      text: "🧪 Test notification from Interactive Dashboard",
      blocks: [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "*Test Webhook Configuration*\n\n" \
                  "Process: `#{@slack_webhook.process}`\n" \
                  "Status: `#{@slack_webhook.status}`\n" \
                  "Webhook Name: #{@slack_webhook.name}"
          }
        },
        {
          type: "context",
          elements: [
            {
              type: "mrkdwn",
              text: "Test performed at: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
            }
          ]
        }
      ]
    }

    result = service.send_message(test_message)

    respond_to do |format|
      if result[:success]
        format.html {
          redirect_to @slack_webhook, notice: "Test successful! Message sent to Slack."
        }
        format.turbo_stream {
          render turbo_stream: turbo_stream.update(
            "webhook_test_result_#{@slack_webhook.id}",
            partial: "test_result",
            locals: { success: true, message: "Test successful! Message sent to Slack." }
          )
        }
        format.json { render json: { success: true, message: "Test successful!" } }
      else
        format.html {
          redirect_to @slack_webhook, alert: "Test failed: #{result[:error]}"
        }
        format.turbo_stream {
          render turbo_stream: turbo_stream.update(
            "webhook_test_result_#{@slack_webhook.id}",
            partial: "test_result",
            locals: { success: false, message: "Test failed: #{result[:error]}" }
          )
        }
        format.json { render json: { success: false, error: result[:error] }, status: :unprocessable_entity }
      end
    end
  end

  def toggle_active
    @slack_webhook.toggle!(:active)

    respond_to do |format|
      format.html {
        redirect_to slack_webhooks_path, notice: "Webhook #{@slack_webhook.active? ? 'activated' : 'deactivated'}."
      }
      format.turbo_stream {
        render turbo_stream: turbo_stream.update(
          "webhook_row_#{@slack_webhook.id}",
          partial: "webhook_row",
          locals: { webhook: @slack_webhook }
        )
      }
    end
  end

  private

  def set_slack_webhook
    @slack_webhook = SlackWebhook.find(params[:id])
  end

  def slack_webhook_params
    params.require(:slack_webhook).permit(:name, :webhook_url, :process, :status, :active, :message_template, :test_mode)
  end
end