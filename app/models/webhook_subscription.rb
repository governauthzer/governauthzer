class WebhookSubscription < ApplicationRecord
  has_many :webhook_deliveries, dependent: :destroy

  # The HMAC key every outbound delivery is signed with. Encrypted at rest for the
  # same reason as auth_providers.oidc_client_secret: a read-only leak of this
  # column hands an attacker the ability to forge `access.approved` deliveries to a
  # customer's provisioner — the signature is the only thing a bridge can trust.
  # Non-deterministic: nothing looks a subscription up by its secret.
  encrypts :signing_secret

  validates :name, presence: true
  validates :endpoint_url, presence: true
  validates :signing_secret, presence: true

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

  private

  def ensure_signing_secret
    self.signing_secret ||= SecureRandom.hex(32)
  end
end
