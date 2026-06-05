require "ipaddr"

# Middleware-layer abuse throttling. Rack::Attack inserts itself into the stack
# via its Railtie; this file defines the rules.
#
# Storage is Rails.cache — Solid Cache in production (per the 2026-05-05 decision),
# memory store in development. Disabled in test by default; the throttle test flips
# `Rack::Attack.enabled` on with a real cache store.
#
# Note on scope: there is NO password/username login surface (auth is OIDC +
# Option-B emergency-login token), so there is deliberately no per-username
# lockout rule — it would defend a credential that doesn't exist. Emergency-login
# tokens are 256-bit; the per-IP throttle below is generic abuse/log-flood
# protection, not the brute-force defense (entropy is).
class Rack::Attack
  # --- backing store ---------------------------------------------------------
  self.cache.store = Rails.cache

  # --- customer-configurable safelist ---------------------------------------
  # RATE_LIMIT_SAFELIST = comma-separated CIDRs (corporate egress, monitoring).
  SAFELIST_CIDRS = ENV.fetch("RATE_LIMIT_SAFELIST", "")
                      .split(",")
                      .filter_map { |c| IPAddr.new(c.strip) rescue nil }

  safelist("safelist by CIDR") do |req|
    SAFELIST_CIDRS.any? { |net| net.include?(req.ip) }
  rescue IPAddr::Error
    false
  end

  # --- API: per-IP and per-token -------------------------------------------
  throttle("api/ip", limit: 600, period: 60) do |req|
    req.ip if req.path.start_with?("/api/v1")
  end

  # Per-consumer (token) limit, higher than per-IP so several consumers can share
  # an egress IP. Keyed by token digest — never the raw secret in the cache key.
  throttle("api/token", limit: 3000, period: 60) do |req|
    next unless req.path.start_with?("/api/v1")

    header = req.get_header("HTTP_AUTHORIZATION").to_s
    if header.start_with?("Bearer ")
      Digest::SHA256.hexdigest(header.sub(/\ABearer\s+/, "").strip)
    end
  end

  # --- Admin UI: per-IP ------------------------------------------------------
  throttle("admin/ip", limit: 300, period: 60) do |req|
    req.ip if req.path.start_with?("/admin")
  end

  # --- Auth surfaces: per-IP -------------------------------------------------
  # OIDC request phase (POST /auth/:slug, handled by OmniAuth middleware).
  throttle("auth/ip", limit: 5, period: 20) do |req|
    req.ip if req.post? && req.path.start_with?("/auth/")
  end

  # Emergency-login redemption — generic abuse limiter (token entropy is the real
  # defense). Catches retry storms and access-log flooding.
  throttle("emergency-login/ip", limit: 5, period: 20) do |req|
    req.ip if req.path.start_with?("/emergency-login/")
  end

  # --- 429 responder ---------------------------------------------------------
  # Mirrors the API error envelope so consumers branch on error.code uniformly.
  self.throttled_responder = lambda do |req|
    match = req.env["rack.attack.match_data"] || {}
    period = match[:period].to_i
    retry_after = period.positive? ? (period - (Time.now.to_i % period)) : 60

    body = {
      "error" => {
        "code" => "rate_limited",
        "message" => "Too many requests; slow down and retry after the indicated interval.",
        "details" => { "retry_after" => retry_after }
      }
    }.to_json

    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [ body ]
    ]
  end
end

Rack::Attack.enabled = false if Rails.env.test?
