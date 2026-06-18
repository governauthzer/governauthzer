require "test_helper"

class Outbound::FanoutJobTest < ActiveJob::TestCase
  def setup
    Current.correlation_id = SecureRandom.uuid
    @app = Application.create!(name: "Slack", slug: "slack")
    @role = Role.create!(application: @app, name: "Member", slug: "member")
    @user = User.create!(email: "ada@example.com", name: "Ada")
    @access = Access.create!(user: @user, role: @role, status: "approved")
    @event = AuditEvent.record!(event_type: "access.approved", actor: :system,
                                targets: [ @user, @access, @role ], metadata: {})
  end

  test "creates a delivery and enqueues DeliveryJob for a matching active subscription" do
    sub = WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://b.example/h")

    assert_difference("WebhookDelivery.count", 1) do
      assert_enqueued_with(job: Outbound::DeliveryJob) do
        Outbound::FanoutJob.perform_now(@event.id)
      end
    end

    delivery = WebhookDelivery.last
    assert_equal sub, delivery.webhook_subscription
    assert_equal @event.id, delivery.audit_event_id
    assert_equal "com.governauthzer.access.approved", delivery.cloud_event_type
    assert_equal "ada@example.com", delivery.payload.dig("data", "user", "email")
  end

  test "skips a subscription scoped to a different application" do
    WebhookSubscription.create!(name: "AWS only", endpoint_url: "https://b/h",
                                application_ids: [ SecureRandom.uuid ])
    assert_no_difference("WebhookDelivery.count") do
      Outbound::FanoutJob.perform_now(@event.id)
    end
  end

  test "an inactive subscription receives nothing" do
    WebhookSubscription.create!(name: "Off", endpoint_url: "https://b/h", active: false)
    assert_no_difference("WebhookDelivery.count") do
      Outbound::FanoutJob.perform_now(@event.id)
    end
  end

  test "fan-out is idempotent — a re-run creates no duplicate and re-enqueues nothing" do
    WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://b/h")
    Outbound::FanoutJob.perform_now(@event.id)

    assert_no_difference("WebhookDelivery.count") do
      assert_no_enqueued_jobs only: Outbound::DeliveryJob do
        Outbound::FanoutJob.perform_now(@event.id)
      end
    end
  end

  test "a non-published event produces no deliveries" do
    WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://b/h")
    other = AuditEvent.record!(event_type: "auth.login.succeeded", actor: @user, targets: [ @user ])
    assert_no_difference("WebhookDelivery.count") do
      Outbound::FanoutJob.perform_now(other.id)
    end
  end

  test "flips an approved grant to provisioning pending when a subscriber matches" do
    WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://b/h")
    assert_equal "not_required", @access.provisioning_status
    Outbound::FanoutJob.perform_now(@event.id)
    assert_equal "pending", @access.reload.provisioning_status
  end

  test "leaves provisioning_status not_required when no subscriber matches" do
    Outbound::FanoutJob.perform_now(@event.id)
    assert_equal "not_required", @access.reload.provisioning_status
  end
end

# The after_create_commit hook itself is exercised by calling the gated method
# directly — after_commit callbacks do not fire inside transactional tests, and
# the wiring (commit-time, allowlist-gated) is the unit worth asserting here.
class Outbound::ProjectionCallbackTest < ActiveJob::TestCase
  test "a published audit type enqueues the fan-out projection" do
    event = AuditEvent.new(event_type: "access.approved")
    assert_enqueued_with(job: Outbound::FanoutJob) do
      event.send(:enqueue_outbound_projection)
    end
  end

  test "a non-published audit type enqueues nothing" do
    event = AuditEvent.new(event_type: "auth.login.succeeded")
    assert_no_enqueued_jobs only: Outbound::FanoutJob do
      event.send(:enqueue_outbound_projection)
    end
  end
end
