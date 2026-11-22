# How this installation notifies people. A single row, edited by an operator in the
# admin UI; read at delivery time, so a change applies to the next message without a
# restart.
class NotificationSetting < ApplicationRecord
  # Encrypted for the same reason as auth_providers.oidc_client_secret: a read-only
  # leak of the table must not hand out a working mail-relay credential, which would
  # let an attacker send mail that passes the organisation's SPF/DKIM checks.
  encrypts :smtp_password

  # Slack, Teams, Discord and Telegram webhook URLs carry their own credential: anyone
  # holding the URL can post into the channel as governauthzer.
  encrypts :messenger_url

  # starttls: plain connection upgraded with STARTTLS, and the upgrade is required —
  #           the `auto` variant silently falls back to cleartext when a man in the
  #           middle strips the capability, so it is not offered.
  # tls:      TLS from the first byte (SMTPS, usually port 465).
  # none:     no encryption; for a relay on the same private network only.
  SMTP_SECURITY_MODES = %w[starttls tls none].freeze

  # An unreachable server must fail the operator's "send test email" click in
  # seconds, not hang the request; Net::SMTP's defaults are 30s and 60s.
  SMTP_TIMEOUT_SECONDS = 10

  # What a messenger template may reference. `text` is the ready-made sentence, which
  # is all most templates need; the rest let an operator compose their own.
  MESSENGER_PLACEHOLDERS = %w[text event requester role application approver justification comment link].freeze
  PLACEHOLDER_PATTERN = /\{\{\s*(\w+)\s*\}\}/

  # Starting points the admin UI fills the template with. Only the envelope differs
  # between messengers; every one of them renders the bare link in `text` as a link.
  MESSENGER_PRESETS = {
    "slack" => { label: "Slack / Mattermost / Rocket.Chat / Google Chat",
                 template: '{"text": "{{text}}"}' },
    "discord" => { label: "Discord", template: '{"content": "{{text}}"}' },
    "telegram" => { label: "Telegram (URL: https://api.telegram.org/bot<token>/sendMessage)",
                    template: '{"chat_id": "<chat id>", "text": "{{text}}"}' },
    "teams" => { label: "Microsoft Teams (Workflows)",
                 template: JSON.pretty_generate(
                   "type" => "message",
                   "attachments" => [ {
                     "contentType" => "application/vnd.microsoft.card.adaptive",
                     "content" => {
                       "$schema" => "http://adaptivecards.io/schemas/adaptive-card.json",
                       "type" => "AdaptiveCard", "version" => "1.4",
                       "body" => [ { "type" => "TextBlock", "text" => "{{text}}", "wrap" => true } ]
                     }
                   } ]
                 ) }
  }.freeze

  # http is allowed for the same reason as on webhook subscriptions: a self-hosted
  # Mattermost on the private network has no certificate. Flagged in the UI.
  MESSENGER_URL_SCHEMES = %w[http https].freeze

  validates :smtp_security, inclusion: { in: SMTP_SECURITY_MODES }
  validates :smtp_port, numericality: { only_integer: true, in: 1..65_535 }
  validates :smtp_host, :mail_from, presence: true, if: :email_enabled?
  validate :mail_from_is_an_address
  validates :messenger_url, presence: true, if: :messenger_enabled?
  validate :messenger_url_is_a_web_address
  validate :messenger_template_renders

  # A password is only ever sent alongside a username; once the username is cleared
  # the stored password is dead weight that a leak could still expose.
  before_save { self.smtp_password = nil if smtp_username.blank? }

  # The last delivery result describes the endpoint it came from; a new URL or
  # template starts with a clean slate rather than an error it never produced.
  before_save :clear_messenger_result, if: -> { will_save_change_to_messenger_url? || will_save_change_to_messenger_template? }

  # The row, or an unsaved one carrying the defaults (email off) before an operator
  # has saved anything. Reading never writes.
  def self.current
    find_or_initialize_by(singleton: true)
  end

  def self.email_enabled?
    current.email_enabled?
  end

  def self.messenger_enabled?
    current.messenger_enabled?
  end

  # Action Mailer :smtp settings for the next delivery.
  def smtp_settings
    settings = {
      address: smtp_host,
      port: smtp_port,
      open_timeout: SMTP_TIMEOUT_SECONDS,
      read_timeout: SMTP_TIMEOUT_SECONDS
    }
    case smtp_security
    when "starttls" then settings[:enable_starttls] = true
    when "tls"      then settings[:tls] = true
    else                 settings[:enable_starttls_auto] = false
    end
    if smtp_username.present?
      settings[:user_name] = smtp_username
      settings[:password] = smtp_password
      settings[:authentication] = :plain
    end
    settings
  end

  # What a test send needs, independent of whether notifications are switched on —
  # so an operator can prove the relay works before turning email on.
  def smtp_configured?
    smtp_host.present? && mail_from.present?
  end

  def messenger_configured?
    messenger_url.present?
  end

  # Enough to tell which endpoint is configured without exposing the credential —
  # shown in the UI and recorded in audit events in place of the URL.
  def saved_messenger_host
    URI.parse(messenger_url_in_database.to_s).host
  rescue URI::InvalidURIError
    nil
  end

  def insecure_messenger_url?
    messenger_uri&.scheme == "http"
  end

  # The request body for one message. The template is parsed as JSON first and the
  # placeholders are substituted inside its string values only, so a quote or brace
  # in a justification can never break the document or add a field to it.
  def render_messenger_body(vars)
    values = vars.to_h.transform_keys(&:to_s)
    JSON.generate(substitute(JSON.parse(messenger_template), values))
  end

  # Operational state, not an operator action: written straight to the columns, with
  # no audit event and no updated_at bump.
  def record_messenger_result!(code:, error:)
    update_columns(messenger_last_response_code: code, messenger_last_error: error,
                   messenger_last_attempted_at: Time.current)
  end

  def audit_display
    "Notification settings"
  end

  private

  def substitute(node, values)
    case node
    when Hash   then node.transform_values { |v| substitute(v, values) }
    when Array  then node.map { |v| substitute(v, values) }
    when String then node.gsub(PLACEHOLDER_PATTERN) { values[$1].to_s }
    else node
    end
  end

  def placeholders_in(node)
    case node
    when Hash   then node.values.flat_map { |v| placeholders_in(v) }
    when Array  then node.flat_map { |v| placeholders_in(v) }
    when String then node.scan(PLACEHOLDER_PATTERN).flatten
    else []
    end
  end

  def messenger_template_renders
    parsed = JSON.parse(messenger_template.to_s)
    return errors.add(:messenger_template, "must be a JSON object or array") unless parsed.is_a?(Hash) || parsed.is_a?(Array)

    unknown = placeholders_in(parsed).uniq - MESSENGER_PLACEHOLDERS
    errors.add(:messenger_template, "uses unknown placeholders: #{unknown.join(', ')}") if unknown.any?
  rescue JSON::ParserError
    errors.add(:messenger_template, "is not valid JSON")
  end

  def messenger_url_is_a_web_address
    return if messenger_url.blank?

    uri = messenger_uri
    unless uri && MESSENGER_URL_SCHEMES.include?(uri.scheme) && uri.host.present?
      errors.add(:messenger_url, "must be an http:// or https:// URL")
    end
  end

  def messenger_uri
    URI.parse(messenger_url.to_s)
  rescue URI::InvalidURIError
    nil
  end

  def clear_messenger_result
    self.messenger_last_response_code = nil
    self.messenger_last_error = nil
    self.messenger_last_attempted_at = nil
  end

  def mail_from_is_an_address
    return if mail_from.blank?

    address = Mail::Address.new(mail_from)
    errors.add(:mail_from, "must be an email address") unless address.address&.include?("@")
  rescue Mail::Field::ParseError
    errors.add(:mail_from, "must be an email address")
  end
end
