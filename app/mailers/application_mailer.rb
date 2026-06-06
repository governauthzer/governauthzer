class ApplicationMailer < ActionMailer::Base
  # From address is per-install configuration (self-hosted) — set MAIL_FROM in the
  # deployment environment; the default is a safe placeholder for dev.
  default from: ENV.fetch("MAIL_FROM", "governauthzer@localhost")
  layout "mailer"
end
