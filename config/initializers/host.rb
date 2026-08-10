# Base host for URL helpers (used by CLI to print absolute URLs).
# Customer sets GOVERNAUTHZER_HOST in production (e.g., https://governauthzer.example.com).
# Dev default: http://localhost:3000.

raw_host = ENV.fetch("GOVERNAUTHZER_HOST", "http://localhost:3000")
uri = URI.parse(raw_host)

# Kept as configured, so anything that has to name THIS deployment — the CloudEvents
# `source`, for one — reads the answer from here instead of restating the default.
Rails.application.config.x.base_url = raw_host

url_options = { protocol: uri.scheme || "http", host: uri.host || raw_host }
url_options[:port] = uri.port if uri.port && uri.port != uri.default_port

Rails.application.routes.default_url_options.merge!(url_options)

# Mailer links must use the same host — otherwise emails point at the framework
# default (e.g. example.com). Set on the live class so it applies regardless of
# Action Mailer railtie ordering.
ActionMailer::Base.default_url_options = url_options
