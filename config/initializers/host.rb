# Base host for URL helpers (used by CLI to print absolute URLs).
# Customer sets GOVERNAUTHZER_HOST in production (e.g., https://governauthzer.example.com).
# Dev default: http://localhost:3000.

raw_host = ENV.fetch("GOVERNAUTHZER_HOST", "http://localhost:3000")
uri = URI.parse(raw_host)

Rails.application.routes.default_url_options[:protocol] = uri.scheme || "http"
Rails.application.routes.default_url_options[:host]     = uri.host || raw_host
Rails.application.routes.default_url_options[:port]     = uri.port if uri.port && uri.port != uri.default_port
