class ApiToken < ApplicationRecord
  PREFIX = "gva_".freeze

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :live, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # Token format: `gva_<43 chars>` — 4-char prefix for grepability + secret-scanner
  # detection, plus 256 bits of entropy from urlsafe_base64(32).
  def self.generate_raw_token
    "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def self.find_by_raw_token(raw_token)
    return nil unless raw_token.is_a?(String) && raw_token.start_with?(PREFIX)
    find_by(token_digest: digest(raw_token))
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def redeemable?
    !expired?
  end
end
