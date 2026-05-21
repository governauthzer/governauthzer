class AuthProvider < ApplicationRecord
  has_many :omniauth_identities, dependent: :restrict_with_error

  encrypts :oidc_client_secret

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :oidc_issuer_url, presence: true
  validates :oidc_client_id, presence: true
  validates :oidc_scope, presence: true
  validate :claim_mappings_is_array

  before_validation :normalize_slug

  scope :enabled, -> { where(enabled: true) }

  def discovery_endpoint
    return nil if oidc_issuer_url.blank?
    "#{oidc_issuer_url.chomp('/')}/.well-known/openid-configuration"
  end

  private

  def normalize_slug
    return if slug.blank?
    self.slug = slug.downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-")
  end

  def claim_mappings_is_array
    errors.add(:claim_mappings, "must be an array") unless claim_mappings.is_a?(Array)
  end
end
