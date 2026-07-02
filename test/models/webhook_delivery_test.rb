require "test_helper"

class WebhookDeliveryTest < ActiveSupport::TestCase
  def setup
    Current.correlation_id = SecureRandom.uuid
    @sub = WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://bridge.example/hooks")
  end

  # Each delivery references a distinct real audit event (FK + the unique
  # (subscription, audit_event_id) index require a fresh event per row).
  def build_delivery(**attrs)
    ev = AuditEvent.record!(event_type: "access.approved", actor: :system, targets: [])
    WebhookDelivery.create!({
      webhook_subscription: @sub,
      audit_event_id: ev.id,
      cloud_event_type: "com.governauthzer.access.approved",
      payload: { "id" => "x" }
    }.merge(attrs))
  end

  test "defaults to pending with zero attempts" do
    d = build_delivery
    assert_equal "pending", d.status
    assert_equal 0, d.attempt_count
  end

  test "stuck scope picks only rows overdue past the grace window" do
    stale_pending  = build_delivery(status: "pending", created_at: 30.minutes.ago)
    fresh_pending  = build_delivery(status: "pending")
    overdue_failed = build_delivery(status: "failed", next_retry_at: 30.minutes.ago)
    barely_failed  = build_delivery(status: "failed", next_retry_at: 1.minute.ago)
    scheduled      = build_delivery(status: "failed", next_retry_at: 1.hour.from_now)
    delivered      = build_delivery(status: "delivered")
    dead           = build_delivery(status: "dead")

    ids = WebhookDelivery.stuck(grace: 10.minutes).pluck(:id)
    assert_includes ids, stale_pending.id
    assert_includes ids, overdue_failed.id
    assert_not_includes ids, fresh_pending.id, "a fresh pending row still has its fanout-enqueued job"
    assert_not_includes ids, barely_failed.id, "a recently-due failed row may still have a live retry job"
    assert_not_includes ids, scheduled.id
    assert_not_includes ids, delivered.id
    assert_not_includes ids, dead.id
  end

  test "backoff grows with attempts and caps at 6h" do
    assert_equal 2.minutes, WebhookDelivery.new(attempt_count: 1).backoff_delay
    assert_equal 8.minutes, WebhookDelivery.new(attempt_count: 3).backoff_delay
    assert_equal 360.minutes, WebhookDelivery.new(attempt_count: 20).backoff_delay
  end
end
