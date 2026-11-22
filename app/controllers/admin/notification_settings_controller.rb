class Admin::NotificationSettingsController < Admin::BaseController
  before_action :load_settings

  def show
  end

  def update
    @settings.assign_attributes(settings_params)
    changed = @settings.changes
    if @settings.save
      record_admin_audit("notification_settings.updated", @settings, attribute_changes: redact_secret_diff(changed))
      redirect_to admin_notification_settings_path, notice: "Notification settings saved."
    else
      render :show, status: :unprocessable_content
    end
  end

  # Sends to the signed-in operator with the SAVED settings, synchronously, so the
  # answer is the SMTP server's own. Works while email is switched off — proving the
  # relay before turning notifications on is the point. Audited either way: it makes
  # the server open a connection to an operator-chosen host with a stored credential.
  def test_email
    unless @settings.persisted? && @settings.smtp_configured?
      return redirect_to admin_notification_settings_path,
                         alert: "Save an SMTP server and a From address first."
    end

    error = deliver_test_email
    record_test_audit("notification_settings.email_tested", error,
                      "recipient" => current_user.email, "smtp_host" => @settings.smtp_host)
    if error
      redirect_to admin_notification_settings_path, alert: "Test email failed: #{error}"
    else
      redirect_to admin_notification_settings_path, notice: "Test email sent to #{current_user.email}."
    end
  end

  # Posts a sample message to the SAVED messenger webhook, synchronously, and shows
  # the endpoint's answer. Like the test email it works while the channel is off, is
  # audited, and its result becomes the channel's last known state.
  def test_messenger
    unless @settings.persisted? && @settings.messenger_configured?
      return redirect_to admin_notification_settings_path, alert: "Save a webhook URL first."
    end

    error = deliver_test_message
    record_test_audit("notification_settings.messenger_tested", error, "host" => @settings.saved_messenger_host)
    if error
      redirect_to admin_notification_settings_path, alert: "Test message failed: #{error}"
    else
      redirect_to admin_notification_settings_path, notice: "Test message posted."
    end
  end

  private

  def load_settings
    @settings = NotificationSetting.current
  end

  # Returns nil on success, or the failure as text. The rescue is deliberately
  # broad: Net::SMTP, OpenSSL, DNS and socket errors share no ancestor, and every
  # one of them is the answer the operator clicked the button to get.
  def deliver_test_email
    NotificationTestMailer.with(email: current_user.email, name: current_user.name).test_email.deliver_now
    nil
  rescue StandardError => e
    "#{e.class.name}: #{e.message}".truncate(300)
  end

  # Returns nil on success, or the failure as text — the endpoint's status and body,
  # or the network error. Rescued broadly for the same reason as the test email.
  def deliver_test_message
    link = root_url
    body = @settings.render_messenger_body(
      "text" => "Test message from governauthzer, sent by #{current_user.name}. " \
                "If you can read this, notifications will arrive here.\n#{link}",
      "event" => "test", "requester" => current_user.name, "role" => "Example role",
      "application" => "Example application", "approver" => current_user.name,
      "justification" => "Testing the notification channel", "comment" => "", "link" => link
    )
    response = Notifications::MessengerDeliveryJob.deliver(@settings, body)
    (200..299).cover?(response.code) ? nil : Notifications::MessengerDeliveryJob.describe(response)
  rescue StandardError => e
    message = "#{e.class.name}: #{e.message}".truncate(Notifications::MessengerDeliveryJob::ERROR_BODY_LIMIT)
    @settings.record_messenger_result!(code: nil, error: message)
    message
  end

  def record_test_audit(event_type, error, details)
    metadata = { "source" => "admin-ui", "outcome" => error ? "failed" : "delivered" }.merge(details)
    metadata["error"] = error if error
    AuditEvent.record!(event_type: event_type, actor: current_user, targets: @settings, metadata: metadata)
  end

  def settings_params
    attrs = params.require(:notification_setting).permit(
      :email_enabled, :smtp_host, :smtp_port, :smtp_security, :smtp_username, :smtp_password, :mail_from,
      :messenger_enabled, :messenger_url, :messenger_template
    )
    # Blank secret fields mean "keep the stored value" — neither is ever rendered back.
    attrs.delete(:smtp_password) if attrs[:smtp_password].blank?
    attrs.delete(:messenger_url) if attrs[:messenger_url].blank?
    attrs
  end

  SECRET_ATTRIBUTES = %w[smtp_password messenger_url].freeze

  def redact_secret_diff(changes)
    SECRET_ATTRIBUTES.each do |attr|
      changes = changes.merge(attr => [ "[REDACTED]", "[REDACTED]" ]) if changes.key?(attr)
    end
    changes
  end
end
