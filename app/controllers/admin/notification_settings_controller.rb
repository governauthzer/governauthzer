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
    record_test_audit(error)
    if error
      redirect_to admin_notification_settings_path, alert: "Test email failed: #{error}"
    else
      redirect_to admin_notification_settings_path, notice: "Test email sent to #{current_user.email}."
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

  def record_test_audit(error)
    metadata = { "source" => "admin-ui", "recipient" => current_user.email, "smtp_host" => @settings.smtp_host,
                 "outcome" => error ? "failed" : "delivered" }
    metadata["error"] = error if error
    AuditEvent.record!(event_type: "notification_settings.email_tested", actor: current_user,
                       targets: @settings, metadata: metadata)
  end

  def settings_params
    attrs = params.require(:notification_setting).permit(
      :email_enabled, :smtp_host, :smtp_port, :smtp_security, :smtp_username, :smtp_password, :mail_from
    )
    # A blank password field means "keep the stored one" — it is never rendered back.
    attrs.delete(:smtp_password) if attrs[:smtp_password].blank?
    attrs
  end

  def redact_secret_diff(changes)
    return changes unless changes.key?("smtp_password")
    changes.merge("smtp_password" => [ "[REDACTED]", "[REDACTED]" ])
  end
end
