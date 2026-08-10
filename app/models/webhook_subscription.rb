class WebhookSubscription < ApplicationRecord
  has_many :webhook_deliveries, dependent: :destroy

  # The HMAC key every outbound delivery is signed with. Encrypted at rest for the
  # same reason as auth_providers.oidc_client_secret: a read-only leak of this
  # column hands an attacker the ability to forge `access.approved` deliveries to a
  # customer's provisioner — the signature is the only thing a bridge can trust.
  # Non-deterministic: nothing looks a subscription up by its secret.
  encrypts :signing_secret

  # http is allowed alongside https on purpose: the recommended shape is a bridge on
  # the deployment's private container network, where the request never leaves the
  # host and an internal name has no certificate to present. It is flagged in the UI
  # rather than refused, because deliveries carry the subject's name and email.
  ENDPOINT_SCHEMES = %w[http https].freeze

  validates :name, presence: true
  validates :endpoint_url, presence: true
  validates :signing_secret, presence: true
  validate :endpoint_url_is_a_web_address

  before_validation :ensure_signing_secret, on: :create

  scope :active, -> { where(active: true) }

  # A subscription receives a published event when it is active and the event's
  # type and application pass its filters. An empty filter means "all" — so the
  # single-bridge reference deployment is one subscription with both filters empty
  # (all types, all apps). The application_ids axis is the SAME axis as the #2
  # reconcile-token resource-scope: they narrow together under multi-bridge setups.
  def matches?(cloud_event_type:, application_id:)
    active? &&
      (event_types.empty? || event_types.include?(cloud_event_type)) &&
      (application_ids.empty? || application_ids.include?(application_id))
  end

  # Deliveries to this endpoint cross the network in clear. True only for a valid
  # http URL — an unparseable one can't be saved, so it can't reach a view.
  def insecure_endpoint?
    endpoint_uri&.scheme == "http"
  end

  private

  def ensure_signing_secret
    self.signing_secret ||= SecureRandom.hex(32)
  end

  # Presence is validated separately; this only judges what a value means. Without
  # it a typo or an `ftp://` paste is accepted and surfaces much later as deliveries
  # that never succeed.
  def endpoint_url_is_a_web_address
    return if endpoint_url.blank?

    uri = endpoint_uri
    return errors.add(:endpoint_url, "is not a valid URL") if uri.nil?

    unless ENDPOINT_SCHEMES.include?(uri.scheme) && uri.host.present?
      errors.add(:endpoint_url, "must be an http:// or https:// URL")
    end
  end

  def endpoint_uri
    URI.parse(endpoint_url.to_s)
  rescue URI::InvalidURIError
    nil
  end
end
