require "test_helper"

class AdminNotificationSettingsTest < ActionDispatch::IntegrationTest
  # Stands in for an SMTP server that refuses the connection.
  class RefusingDelivery
    def initialize(_settings) = nil
    def deliver!(_mail) = raise(Errno::ECONNREFUSED, "connect(2) for smtp.example.com port 587")
  end
  ActionMailer::Base.add_delivery_method :refusing, RefusingDelivery

  def setup
    @self_app = Application.create!(name: "Governauthzer", slug: Application::SELF_SLUG)
    operator_role = @self_app.roles.create!(name: "Operator", slug: "operator", protected: true)
    @operator = User.create!(email: "notifyop@example.com", name: "Notify Op")
    Access.create!(user: @operator, role: operator_role, status: "approved", source: "manual")
    sign_in_as @operator
    ActionMailer::Base.deliveries.clear
  end

  def settings_params(**overrides)
    {
      email_enabled: "1", smtp_host: "smtp.example.com", smtp_port: "587", smtp_security: "starttls",
      smtp_username: "mailer", smtp_password: "s3cret", mail_from: "gov@example.com"
    }.merge(overrides)
  end

  test "a non-operator is forbidden" do
    plain = User.create!(email: "plain@example.com", name: "Plain")
    sign_in_as plain
    get "/admin/notification_settings"
    assert_response :forbidden
    patch "/admin/notification_settings", params: { notification_setting: settings_params }
    assert_response :forbidden
    assert_not NotificationSetting.exists?
  end

  test "renders before anything is saved, with email off" do
    get "/admin/notification_settings"
    assert_response :ok
    assert_includes response.body, "Send email notifications"
  end

  test "operator saves the settings, emitting an audit event with the password redacted" do
    assert_difference("AuditEvent.where(event_type: 'notification_settings.updated').count", 1) do
      patch "/admin/notification_settings", params: { notification_setting: settings_params }
    end
    assert_redirected_to "/admin/notification_settings"

    settings = NotificationSetting.current
    assert settings.email_enabled?
    assert_equal "s3cret", settings.smtp_password

    event = AuditEvent.where(event_type: "notification_settings.updated").order(:occurred_at).last
    assert_equal [ "[REDACTED]", "[REDACTED]" ], event.attribute_changes["smtp_password"]
    assert_not_includes event.attribute_changes.to_json, "s3cret"
  end

  test "the password is never rendered back, and a blank field keeps it" do
    patch "/admin/notification_settings", params: { notification_setting: settings_params }
    get "/admin/notification_settings"
    assert_not_includes response.body, "s3cret"

    patch "/admin/notification_settings", params: { notification_setting: settings_params(smtp_password: "", smtp_port: "2525") }
    settings = NotificationSetting.current
    assert_equal 2525, settings.smtp_port
    assert_equal "s3cret", settings.smtp_password
  end

  test "switching email on without a server re-renders unprocessable and saves nothing" do
    assert_no_difference([ "NotificationSetting.count", "AuditEvent.count" ]) do
      patch "/admin/notification_settings", params: { notification_setting: settings_params(smtp_host: "") }
    end
    assert_response :unprocessable_content
  end

  test "a test email goes to the operator with the saved settings, even while email is off, and is audited" do
    patch "/admin/notification_settings", params: { notification_setting: settings_params(email_enabled: "0") }

    assert_difference("AuditEvent.where(event_type: 'notification_settings.email_tested').count", 1) do
      assert_emails(1) { post "/admin/notification_settings/test_email" }
    end
    assert_redirected_to "/admin/notification_settings"
    assert_match "Test email sent", flash[:notice]
    assert_equal [ @operator.email ], ActionMailer::Base.deliveries.last.to

    event = AuditEvent.where(event_type: "notification_settings.email_tested").order(:occurred_at).last
    assert_equal "delivered", event.metadata["outcome"]
    assert_equal "smtp.example.com", event.metadata["smtp_host"]
  end

  test "a refused test email shows the server's error and is audited as failed" do
    patch "/admin/notification_settings", params: { notification_setting: settings_params }
    previous = NotificationTestMailer.delivery_method
    NotificationTestMailer.delivery_method = :refusing

    post "/admin/notification_settings/test_email"
    assert_redirected_to "/admin/notification_settings"
    assert_match "Errno::ECONNREFUSED", flash[:alert]

    event = AuditEvent.where(event_type: "notification_settings.email_tested").order(:occurred_at).last
    assert_equal "failed", event.metadata["outcome"]
    assert_match "ECONNREFUSED", event.metadata["error"]
  ensure
    NotificationTestMailer.delivery_method = previous
  end

  test "a test email before any SMTP server is saved is refused without sending" do
    assert_no_difference("AuditEvent.count") do
      assert_no_emails { post "/admin/notification_settings/test_email" }
    end
    assert_redirected_to "/admin/notification_settings"
    assert_match "Save an SMTP server", flash[:alert]
  end

  private

  def sign_in_as(user)
    raw = SecureRandom.urlsafe_base64(32)
    EmergencyToken.create!(user: user, token_digest: EmergencyToken.digest(raw),
                           reason: "test sign-in", expires_at: 5.minutes.from_now)
    get "/emergency-login/#{raw}"
  end
end
