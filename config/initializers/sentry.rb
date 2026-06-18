# Error tracking is opt-in and self-hosted-friendly, the same shape as SMTP and the
# rest of governauthzer's infra config: with no SENTRY_DSN set the SDK is never
# initialized and nothing leaves the process. Set SENTRY_DSN to a self-hosted Sentry
# or a Sentry.io tenant to activate.
if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.breadcrumbs_logger = [ :active_support_logger, :http_logger ]

    # This app holds identity and HR data — never capture PII by default. Request
    # bodies, cookies, and user context are withheld unless an operator explicitly
    # accepts the tradeoff with SENTRY_SEND_PII=true. Rails' filter_parameters
    # (which already includes :email, :secret, :token, ...) still scrubs what is sent.
    config.send_default_pii = ENV["SENTRY_SEND_PII"] == "true"

    config.environment = ENV.fetch("SENTRY_ENVIRONMENT", Rails.env.to_s)
    config.release = ENV["GOVERNAUTHZER_RELEASE"] if ENV["GOVERNAUTHZER_RELEASE"].present?

    # Performance tracing is off by default; set a 0.0..1.0 sample rate to enable.
    config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", "0.0").to_f
  end
end
