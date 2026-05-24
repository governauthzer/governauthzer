# Multi-IdP OIDC via a single registered strategy.
#
# OmniAuth's classic pattern is one strategy per provider, registered at boot.
# We register one openid_connect strategy and override request_path/callback_path
# so it matches ANY `/auth/:slug` where slug corresponds to an enabled
# auth_providers row. The setup lambda runs per request, looks up the
# AuthProvider, and configures the strategy with that row's client_id/secret/issuer.

REQUEST_PATH  = %r{\A/auth/([a-z0-9-]+)\z}
CALLBACK_PATH = %r{\A/auth/([a-z0-9-]+)/callback\z}
RESERVED_PATH_SEGMENTS = %w[failure].freeze

omniauth_setup = lambda do |env|
  path = env["PATH_INFO"]
  match = path.match(REQUEST_PATH) || path.match(CALLBACK_PATH)
  slug = match && match[1]

  provider = AuthProvider.enabled.find_by(slug: slug) if slug
  raise "unknown_or_disabled_provider:#{slug}" unless provider

  base_url = Rails.application.routes.default_url_options.then do |o|
    port_suffix = o[:port].nil? ? "" : ":#{o[:port]}"
    "#{o[:protocol]}://#{o[:host]}#{port_suffix}"
  end

  # The strategy builds the discovery URL from client_options.scheme/host/port
  # (not from `issuer`), defaulting to https/nil/443. We MUST parse the issuer
  # URL and propagate scheme/host/port — otherwise an http://localhost:8080
  # issuer triggers HTTPS-to-port-8080 SSL handshake failures.
  issuer_uri = URI.parse(provider.oidc_issuer_url)

  strategy = env["omniauth.strategy"]
  strategy.options[:issuer]    = provider.oidc_issuer_url
  strategy.options[:discovery] = true
  strategy.options[:scope]     = provider.oidc_scope.split(/\s+/).map(&:to_sym)
  strategy.options[:client_options] ||= {}
  strategy.options[:client_options].merge!(
    identifier:   provider.oidc_client_id,
    secret:       provider.oidc_client_secret,
    redirect_uri: "#{base_url}/auth/#{slug}/callback",
    scheme:       issuer_uri.scheme,
    host:         issuer_uri.host,
    port:         issuer_uri.port
  )
end

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :openid_connect,
    name: :openid_connect,
    setup: omniauth_setup,
    request_path: ->(env) {
      m = env["PATH_INFO"].match(REQUEST_PATH)
      m && !RESERVED_PATH_SEGMENTS.include?(m[1])
    },
    callback_path: ->(env) {
      m = env["PATH_INFO"].match(CALLBACK_PATH)
      m && !RESERVED_PATH_SEGMENTS.include?(m[1])
    }
end

OmniAuth.config.allowed_request_methods = [ :post ]
OmniAuth.config.silence_get_warning     = true

# OIDC spec mandates HTTPS for discovery. The `swd` gem hardcodes `URI::HTTPS` as
# the global discovery URL builder. In development we relax this so a local Keycloak
# on http://localhost:8080 can be discovered. In production the default stays HTTPS;
# customers running on plain HTTP are out of spec and unsupported.
if Rails.env.development? || Rails.env.test?
  require "swd"
  SWD.url_builder = URI::HTTP
end
