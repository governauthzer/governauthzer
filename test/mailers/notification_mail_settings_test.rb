require "test_helper"

# How mailers pick up the operator's notification settings at build time.
class NotificationMailSettingsTest < ActionMailer::TestCase
  def setup
    NotificationSetting.create!(email_enabled: true, smtp_host: "smtp.example.com", smtp_port: 2525,
                                smtp_username: "mailer", smtp_password: "s3cret",
                                mail_from: "Access Requests <access@example.com>")
  end

  def build_test_email
    NotificationTestMailer.with(email: "op@example.com", name: "Op").test_email.message
  end

  test "the From address comes from the settings" do
    message = build_test_email
    assert_equal [ "access@example.com" ], message.from
    assert_equal [ "op@example.com" ], message.to
  end

  test "an SMTP delivery uses the server from the settings" do
    previous = NotificationTestMailer.delivery_method
    NotificationTestMailer.delivery_method = :smtp
    settings = build_test_email.delivery_method.settings
    assert_equal "smtp.example.com", settings[:address]
    assert_equal 2525, settings[:port]
    assert_equal "mailer", settings[:user_name]
    assert_equal "s3cret", settings[:password]
  ensure
    NotificationTestMailer.delivery_method = previous
  end

  test "a change to the settings applies to the next message" do
    NotificationSetting.current.update!(mail_from: "new@example.com")
    assert_equal [ "new@example.com" ], build_test_email.from
  end

  test "an access notification already queued is dropped once email is switched off" do
    NotificationSetting.current.update!(email_enabled: false)
    message = AccessMailer.with(email: "ada@example.com", name: "Ada", role_name: "Member",
                                application_name: "Slack").request_approved
    assert_no_emails { message.deliver_now }
  end

  test "an access notification is delivered while email is on" do
    message = AccessMailer.with(email: "ada@example.com", name: "Ada", role_name: "Member",
                                application_name: "Slack").request_approved
    assert_emails(1) { message.deliver_now }
  end
end
