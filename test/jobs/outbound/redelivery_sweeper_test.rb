require "test_helper"

class Outbound::RedeliverySweeperTest < ActiveJob::TestCase
  def setup
    Current.correlation_id = SecureRandom.uuid
    @sub = WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://bridge.example/hooks")
  end

  def build_delivery(**attrs)
    ev = AuditEvent.record!(event_type: "access.approved", actor: :system, targets: [])
    WebhookDelivery.create!({
      webhook_subscription: @sub,
      audit_event_id: ev.id,
      cloud_event_type: "com.governauthzer.access.approved",
      payload: { "id" => "x" }
    }.merge(attrs))
  end

  test "re-enqueues DeliveryJob for rows stuck past the grace window" do
    stale_pending  = build_delivery(status: "pending", created_at: 30.minutes.ago)
    overdue_failed = build_delivery(status: "failed", next_retry_at: 30.minutes.ago)

    Outbound::RedeliverySweeper.perform_now

    assert_enqueued_with(job: Outbound::DeliveryJob, args: [ stale_pending.id ])
    assert_enqueued_with(job: Outbound::DeliveryJob, args: [ overdue_failed.id ])
  end

  test "leaves fresh, scheduled, delivered and dead rows alone" do
    build_delivery(status: "pending")
    build_delivery(status: "failed", next_retry_at: 1.minute.ago)
    build_delivery(status: "failed", next_retry_at: 1.hour.from_now)
    build_delivery(status: "delivered")
    build_delivery(status: "dead")

    assert_no_enqueued_jobs only: Outbound::DeliveryJob do
      Outbound::RedeliverySweeper.perform_now
    end
  end
end
