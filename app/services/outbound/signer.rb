module Outbound
  # HMAC-SHA256 signature for outbound webhook delivery (Stripe-style: the
  # signature covers "<timestamp>.<body>" so a consumer can reject replays by
  # checking the timestamp's freshness as well as the signature). The shared
  # secret is the subscription's `signing_secret`.
  class Signer
    def self.signature(secret:, timestamp:, body:)
      digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
      "sha256=#{digest}"
    end
  end
end
