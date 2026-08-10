require "test_helper"

class WebhookSubscriptionTest < ActiveSupport::TestCase
  test "generates a signing secret on create when blank" do
    sub = WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://bridge.example/hooks")
    assert sub.signing_secret.present?
  end

  test "signing_secret is encrypted at rest" do
    sub = WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://bridge.example/hooks",
                                      signing_secret: "s1gn1ng-k3y")

    assert_equal "s1gn1ng-k3y", sub.reload.signing_secret, "decrypts on read"
    assert_not_equal "s1gn1ng-k3y", sub.ciphertext_for(:signing_secret),
                     "stored ciphertext differs from plaintext"
  end

  test "a rotated secret is not written to the audit log" do
    sub = WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://bridge.example/hooks")
    old_secret = sub.signing_secret

    sub.update!(signing_secret: SecureRandom.hex(32))

    recorded = AuditEvent.pluck(:attribute_changes, :metadata).flatten.compact.to_json
    assert_not_includes recorded, old_secret
    assert_not_includes recorded, sub.signing_secret
  end

  test "matches? treats empty filters as wildcards (single-bridge reference deployment)" do
    sub = WebhookSubscription.new(active: true, event_types: [], application_ids: [])
    assert sub.matches?(cloud_event_type: "com.governauthzer.access.approved", application_id: SecureRandom.uuid)
  end

  test "matches? filters by event_types and application_ids" do
    app_id = SecureRandom.uuid
    sub = WebhookSubscription.new(active: true,
      event_types: [ "com.governauthzer.access.revoked" ], application_ids: [ app_id ])

    assert_not sub.matches?(cloud_event_type: "com.governauthzer.access.approved", application_id: app_id)
    assert_not sub.matches?(cloud_event_type: "com.governauthzer.access.revoked", application_id: SecureRandom.uuid)
    assert sub.matches?(cloud_event_type: "com.governauthzer.access.revoked", application_id: app_id)
  end

  test "inactive subscription matches nothing" do
    sub = WebhookSubscription.new(active: false, event_types: [], application_ids: [])
    assert_not sub.matches?(cloud_event_type: "com.governauthzer.access.approved", application_id: SecureRandom.uuid)
  end
end
