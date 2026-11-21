require "test_helper"

class NotificationSettingTest < ActiveSupport::TestCase
  def valid_attrs(**overrides)
    { email_enabled: true, smtp_host: "smtp.example.com", mail_from: "gov@example.com" }.merge(overrides)
  end

  test "current returns unsaved defaults with email off, without writing a row" do
    assert_no_difference("NotificationSetting.count") do
      settings = NotificationSetting.current
      assert settings.new_record?
      assert_not settings.email_enabled?
      assert_equal 587, settings.smtp_port
      assert_equal "starttls", settings.smtp_security
    end
    assert_not NotificationSetting.email_enabled?
  end

  test "current returns the saved row" do
    saved = NotificationSetting.create!(valid_attrs)
    assert_equal saved, NotificationSetting.current
    assert NotificationSetting.email_enabled?
  end

  test "the database refuses a second row" do
    NotificationSetting.create!(valid_attrs)
    assert_raises(ActiveRecord::RecordNotUnique) { NotificationSetting.create!(valid_attrs) }
  end

  test "switching email on requires a server and a From address" do
    settings = NotificationSetting.new(email_enabled: true)
    assert_not settings.valid?
    assert settings.errors.of_kind?(:smtp_host, :blank)
    assert settings.errors.of_kind?(:mail_from, :blank)
  end

  test "email off may be saved half-filled" do
    assert NotificationSetting.new(email_enabled: false, smtp_host: "smtp.example.com").valid?
  end

  test "rejects an unknown encryption mode, an out-of-range port and a From that is not an address" do
    assert_not NotificationSetting.new(valid_attrs(smtp_security: "ssl3")).valid?
    assert_not NotificationSetting.new(valid_attrs(smtp_port: 0)).valid?
    assert_not NotificationSetting.new(valid_attrs(smtp_port: 70_000)).valid?
    assert_not NotificationSetting.new(valid_attrs(mail_from: "not an address")).valid?
    assert NotificationSetting.new(valid_attrs(mail_from: "Access Requests <access@example.com>")).valid?
  end

  test "starttls is required, never opportunistic" do
    settings = NotificationSetting.new(valid_attrs(smtp_security: "starttls")).smtp_settings
    assert_equal true, settings[:enable_starttls]
    assert_nil settings[:enable_starttls_auto]
    assert_nil settings[:tls]
  end

  test "tls mode speaks TLS from the first byte" do
    settings = NotificationSetting.new(valid_attrs(smtp_security: "tls", smtp_port: 465)).smtp_settings
    assert_equal true, settings[:tls]
    assert_equal 465, settings[:port]
  end

  test "none mode switches STARTTLS off explicitly" do
    settings = NotificationSetting.new(valid_attrs(smtp_security: "none")).smtp_settings
    assert_equal false, settings[:enable_starttls_auto]
    assert_nil settings[:enable_starttls]
  end

  test "credentials and timeouts are passed only as configured" do
    anonymous = NotificationSetting.new(valid_attrs).smtp_settings
    assert_nil anonymous[:user_name]
    assert_nil anonymous[:authentication]
    assert_equal NotificationSetting::SMTP_TIMEOUT_SECONDS, anonymous[:open_timeout]
    assert_equal NotificationSetting::SMTP_TIMEOUT_SECONDS, anonymous[:read_timeout]

    authed = NotificationSetting.new(valid_attrs(smtp_username: "mailer", smtp_password: "s3cret")).smtp_settings
    assert_equal "mailer", authed[:user_name]
    assert_equal "s3cret", authed[:password]
    assert_equal :plain, authed[:authentication]
  end

  test "the SMTP password is encrypted at rest" do
    settings = NotificationSetting.create!(valid_attrs(smtp_username: "mailer", smtp_password: "s3cret"))
    raw = NotificationSetting.connection.select_value(
      "SELECT smtp_password FROM notification_settings WHERE id = #{NotificationSetting.connection.quote(settings.id)}"
    )
    assert_not_includes raw, "s3cret"
    assert_equal "s3cret", settings.reload.smtp_password
  end

  test "clearing the username drops the stored password" do
    settings = NotificationSetting.create!(valid_attrs(smtp_username: "mailer", smtp_password: "s3cret"))
    settings.update!(smtp_username: "")
    assert_nil settings.reload.smtp_password
  end
end
