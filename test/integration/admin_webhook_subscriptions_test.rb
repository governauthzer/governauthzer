require "test_helper"

class AdminWebhookSubscriptionsTest < ActionDispatch::IntegrationTest
  def setup
    @self_app = Application.create!(name: "Governauthzer", slug: Application::SELF_SLUG)
    operator_role = @self_app.roles.create!(name: "Operator", slug: "operator", protected: true)
    @operator = User.create!(email: "op@example.com", name: "Op")
    Access.create!(user: @operator, role: operator_role, status: "approved", source: "manual")
    @slack = Application.create!(name: "Slack", slug: "slack")
    sign_in_as @operator
  end

  test "operator creates a subscription with a generated signing secret" do
    assert_difference([ "WebhookSubscription.count",
                        "AuditEvent.where(event_type: 'webhook_subscription.created').count" ], 1) do
      post "/admin/webhook_subscriptions", params: {
        webhook_subscription: {
          name: "Bridge", endpoint_url: "https://bridge.internal/hooks", active: "1",
          event_types: [ "com.governauthzer.access.approved" ], application_ids: [ @slack.id ]
        }
      }
    end
    sub = WebhookSubscription.find_by!(name: "Bridge")
    assert sub.signing_secret.present?
    assert_equal [ "com.governauthzer.access.approved" ], sub.event_types
    assert_equal [ @slack.id ], sub.application_ids
    assert_redirected_to admin_webhook_subscription_path(sub)
  end

  test "empty filters mean all (wildcard)" do
    post "/admin/webhook_subscriptions", params: {
      webhook_subscription: { name: "Catch-all", endpoint_url: "https://b/h", active: "1" }
    }
    sub = WebhookSubscription.find_by!(name: "Catch-all")
    assert_empty sub.event_types
    assert_empty sub.application_ids
  end

  test "operator edits, rotates the secret, and deletes a subscription" do
    sub = WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://b/h")
    original_secret = sub.signing_secret

    patch "/admin/webhook_subscriptions/#{sub.id}", params: {
      webhook_subscription: { name: "Bridge v2", endpoint_url: "https://b/h", active: "0" }
    }
    assert_equal "Bridge v2", sub.reload.name
    assert_not sub.active?

    assert_difference("AuditEvent.where(event_type: 'webhook_subscription.secret_rotated').count", 1) do
      post "/admin/webhook_subscriptions/#{sub.id}/rotate_secret"
    end
    assert_not_equal original_secret, sub.reload.signing_secret

    assert_difference("WebhookSubscription.count", -1) do
      delete "/admin/webhook_subscriptions/#{sub.id}"
    end
  end

  test "index and show render" do
    sub = WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://b/h")
    get "/admin/webhook_subscriptions"
    assert_response :ok
    assert_includes response.body, "Bridge"
    get "/admin/webhook_subscriptions/#{sub.id}"
    assert_response :ok
    assert_includes response.body, sub.signing_secret
  end

  test "a non-operator is forbidden" do
    plain = User.create!(email: "plain@example.com", name: "Plain")
    sign_in_as plain
    get "/admin/webhook_subscriptions"
    assert_response :forbidden
  end

  private

  def sign_in_as(user)
    raw = SecureRandom.urlsafe_base64(32)
    EmergencyToken.create!(user: user, token_digest: EmergencyToken.digest(raw),
                           reason: "test sign-in", expires_at: 5.minutes.from_now)
    get "/emergency-login/#{raw}"
  end
end
