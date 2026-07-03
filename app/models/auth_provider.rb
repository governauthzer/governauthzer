class AuthProvider < ApplicationRecord
  include Sluggable

  has_many :omniauth_identities, dependent: :restrict_with_error

  encrypts :oidc_client_secret

  # Holds the unparsed textarea string when claim_mappings= was given a String —
  # so a failed JSON parse can re-render the form with the operator's original input
  # rather than swallowing it.
  attr_reader :claim_mappings_raw

  validates :name, presence: true
  validates :slug, uniqueness: true
  validates :oidc_issuer_url, presence: true
  validates :oidc_client_id, presence: true
  validates :oidc_scope, presence: true
  validate :claim_mappings_valid

  scope :enabled, -> { where(enabled: true) }

  def discovery_endpoint
    return nil if oidc_issuer_url.blank?
    "#{oidc_issuer_url.chomp('/')}/.well-known/openid-configuration"
  end

  # Accept either a String (from form textarea — parse JSON) or an Array/Hash
  # (from internal code or DB load — pass through). Invalid JSON is captured so the
  # validator can report it.
  def claim_mappings=(value)
    case value
    when String
      @claim_mappings_raw = value
      stripped = value.strip
      if stripped.empty?
        @claim_mappings_json_error = nil
        super([])
      else
        begin
          parsed = JSON.parse(stripped)
          @claim_mappings_json_error = nil
          super(parsed)
        rescue JSON::ParserError => e
          @claim_mappings_json_error = e.message
          super([])
        end
      end
    else
      @claim_mappings_raw = nil
      @claim_mappings_json_error = nil
      super(value)
    end
  end

  private

  def claim_mappings_valid
    if @claim_mappings_json_error
      errors.add(:claim_mappings, "is not valid JSON: #{@claim_mappings_json_error}")
    elsif !claim_mappings.is_a?(Array)
      errors.add(:claim_mappings, "must be a JSON array")
    end
  end
end
