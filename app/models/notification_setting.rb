# How this installation notifies people. A single row, edited by an operator in the
# admin UI; read at delivery time, so a change applies to the next message without a
# restart.
class NotificationSetting < ApplicationRecord
  # Encrypted for the same reason as auth_providers.oidc_client_secret: a read-only
  # leak of the table must not hand out a working mail-relay credential, which would
  # let an attacker send mail that passes the organisation's SPF/DKIM checks.
  encrypts :smtp_password

  # starttls: plain connection upgraded with STARTTLS, and the upgrade is required —
  #           the `auto` variant silently falls back to cleartext when a man in the
  #           middle strips the capability, so it is not offered.
  # tls:      TLS from the first byte (SMTPS, usually port 465).
  # none:     no encryption; for a relay on the same private network only.
  SMTP_SECURITY_MODES = %w[starttls tls none].freeze

  # An unreachable server must fail the operator's "send test email" click in
  # seconds, not hang the request; Net::SMTP's defaults are 30s and 60s.
  SMTP_TIMEOUT_SECONDS = 10

  validates :smtp_security, inclusion: { in: SMTP_SECURITY_MODES }
  validates :smtp_port, numericality: { only_integer: true, in: 1..65_535 }
  validates :smtp_host, :mail_from, presence: true, if: :email_enabled?
  validate :mail_from_is_an_address

  # A password is only ever sent alongside a username; once the username is cleared
  # the stored password is dead weight that a leak could still expose.
  before_save { self.smtp_password = nil if smtp_username.blank? }

  # The row, or an unsaved one carrying the defaults (email off) before an operator
  # has saved anything. Reading never writes.
  def self.current
    find_or_initialize_by(singleton: true)
  end

  def self.email_enabled?
    current.email_enabled?
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

  def audit_display
    "Notification settings"
  end

  private

  def mail_from_is_an_address
    return if mail_from.blank?

    address = Mail::Address.new(mail_from)
    errors.add(:mail_from, "must be an email address") unless address.address&.include?("@")
  rescue Mail::Field::ParseError
    errors.add(:mail_from, "must be an email address")
  end
end
