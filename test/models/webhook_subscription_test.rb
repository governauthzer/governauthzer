require "test_helper"

class WebhookSubscriptionTest < ActiveSupport::TestCase
  test "generates a signing secret on create when blank" do
    sub = WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://bridge.example/hooks")
    assert sub.signing_secret.present?
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
