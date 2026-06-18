class ApiToken < ApplicationRecord
  PREFIX = "gva_".freeze
  # Action-scope, orthogonal to the source-scope below. `full` = management token
  # (all endpoints); `reconcile` = may ONLY post reconciliation status. The
  # management API enforces `full` by default (Api::V1::BaseController); only the
  # reconciliation + whoami endpoints accept a `reconcile` token.
  SCOPES = %w[full reconcile].freeze

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :scope, inclusion: { in: SCOPES }

  # Source is normalized identically to ExternalIdentity#source so the snapshot
  # diff can match `external_identities WHERE source = token.source` directly.
  # NULL = full-access management token; non-NULL = HRIS-sync token locked to
  # exactly one source (Decision 1: token scope is the auth boundary).
  before_validation :normalize_source

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

  # True when this token is scoped to a single HRIS source (sync agent token).
  def sync_scoped?
    source.present?
  end

  def full_access?
    scope == "full"
  end

  def reconcile_scoped?
    scope == "reconcile"
  end

  private

  def normalize_source
    self.source = ExternalIdentity.normalize_source(source)
  end
end
