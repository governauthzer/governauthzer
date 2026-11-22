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

class NotificationSettingMessengerTest < ActiveSupport::TestCase
  def messenger(**attrs)
    NotificationSetting.new({ messenger_enabled: true, messenger_url: "https://hooks.example.com/T1/B2/secret" }.merge(attrs))
  end

  test "switching the messenger on requires a URL" do
    settings = NotificationSetting.new(messenger_enabled: true)
    assert_not settings.valid?
    assert settings.errors.of_kind?(:messenger_url, :blank)
  end

  test "the URL must be an http or https address" do
    assert_not messenger(messenger_url: "ftp://hooks.example.com/x").valid?
    assert_not messenger(messenger_url: "hooks.example.com/x").valid?
    assert messenger(messenger_url: "http://mattermost.internal/hooks/abc").valid?
    assert messenger(messenger_url: "http://mattermost.internal/hooks/abc").insecure_messenger_url?
  end

  test "the template must be a JSON object or array using known placeholders" do
    assert_not messenger(messenger_template: "{ broken").valid?
    assert_not messenger(messenger_template: '"just a string"').valid?
    invalid = messenger(messenger_template: '{"text": "{{txet}}"}')
    assert_not invalid.valid?
    assert_match "txet", invalid.errors[:messenger_template].join
    assert messenger(messenger_template: '{"text": "{{ requester }} wants {{role}}"}').valid?
  end

  test "every preset is a valid template" do
    NotificationSetting::MESSENGER_PRESETS.each do |key, preset|
      assert messenger(messenger_template: preset[:template]).valid?, "preset #{key} must validate"
    end
  end

  test "rendering fills placeholders inside string values only, so values cannot break out" do
    settings = messenger(messenger_template: '{"text": "{{text}}", "meta": ["{{event}}", 1, true]}')
    hostile = %q(need it", "admin": true, "x": "{{event}}) + "\n}"
    body = JSON.parse(settings.render_messenger_body("text" => hostile, "event" => "approved"))

    assert_equal [ "meta", "text" ], body.keys.sort, "a value must never add a field"
    assert_equal hostile, body["text"], "a value is inserted verbatim, not re-expanded"
    assert_equal [ "approved", 1, true ], body["meta"]
  end

  test "an unset placeholder renders empty" do
    body = messenger(messenger_template: '{"text": "[{{comment}}]"}').render_messenger_body("text" => "x")
    assert_equal({ "text" => "[]" }, JSON.parse(body))
  end

  test "the webhook URL is encrypted at rest, and only its host is exposed" do
    settings = NotificationSetting.create!(messenger_enabled: true, messenger_url: "https://hooks.example.com/T1/B2/secret")
    raw = NotificationSetting.connection.select_value(
      "SELECT messenger_url FROM notification_settings WHERE id = #{NotificationSetting.connection.quote(settings.id)}"
    )
    assert_not_includes raw, "secret"
    assert_equal "hooks.example.com", settings.reload.saved_messenger_host
  end

  test "a new URL or template clears the last delivery result, other edits keep it" do
    settings = NotificationSetting.create!(messenger_enabled: true, messenger_url: "https://hooks.example.com/a")
    settings.record_messenger_result!(code: 403, error: "HTTP 403: invalid_token")

    settings.update!(mail_from: "gov@example.com")
    assert_equal 403, settings.reload.messenger_last_response_code

    settings.update!(messenger_url: "https://hooks.example.com/b")
    settings.reload
    assert_nil settings.messenger_last_response_code
    assert_nil settings.messenger_last_error
    assert_nil settings.messenger_last_attempted_at
  end

  test "recording a result touches neither updated_at nor validation" do
    settings = NotificationSetting.create!(messenger_enabled: true, messenger_url: "https://hooks.example.com/a")
    before = settings.updated_at
    travel 1.minute do
      settings.record_messenger_result!(code: 200, error: nil)
    end
    settings.reload
    assert_equal 200, settings.messenger_last_response_code
    assert_equal before, settings.updated_at
    assert settings.messenger_last_attempted_at.present?
  end
end
