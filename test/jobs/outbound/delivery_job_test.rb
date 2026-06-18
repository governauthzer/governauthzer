require "test_helper"

class Outbound::DeliveryJobTest < ActiveJob::TestCase
  # Minimal swappable transport (minitest/mock is unavailable in this minitest).
  class FakePoster
    def initialize(&block) = (@block = block)
    def post(**kwargs) = @block.call(**kwargs)
  end

  def setup
    Current.correlation_id = SecureRandom.uuid
    @sub = WebhookSubscription.create!(name: "Bridge", endpoint_url: "https://bridge.example/hooks")
    event = AuditEvent.record!(event_type: "access.approved", actor: :system, targets: [])
    @delivery = WebhookDelivery.create!(
      webhook_subscription: @sub, audit_event_id: event.id,
      cloud_event_type: "com.governauthzer.access.approved",
      payload: { "id" => event.id, "type" => "com.governauthzer.access.approved" }
    )
  end

  def teardown
    Outbound::DeliveryJob.http_poster = Outbound::HttpPoster
  end

  def with_poster(&block)
    Outbound::DeliveryJob.http_poster = FakePoster.new(&block)
  end

  def ok = Outbound::HttpPoster::Response.new(code: 200, body: "")
  def server_error = Outbound::HttpPoster::Response.new(code: 500, body: "boom")

  test "a 2xx response marks the delivery delivered" do
    with_poster { |**| ok }
    Outbound::DeliveryJob.perform_now(@delivery.id)

    @delivery.reload
    assert_equal "delivered", @delivery.status
    assert_equal 1, @delivery.attempt_count
    assert_equal 200, @delivery.last_response_code
    assert @delivery.delivered_at.present?
  end

  test "a non-2xx response marks it failed and self-reschedules" do
    with_poster { |**| server_error }
    assert_enqueued_with(job: Outbound::DeliveryJob) do
      Outbound::DeliveryJob.perform_now(@delivery.id)
    end

    @delivery.reload
    assert_equal "failed", @delivery.status
    assert_equal 1, @delivery.attempt_count
    assert_equal 500, @delivery.last_response_code
    assert @delivery.next_retry_at.present?
  end

  test "a network error is treated as a transient failure" do
    with_poster { |**| raise Errno::ECONNREFUSED }
    Outbound::DeliveryJob.perform_now(@delivery.id)

    @delivery.reload
    assert_equal "failed", @delivery.status
    assert @delivery.last_error.present?
  end

  test "exhausting MAX_ATTEMPTS marks it dead and stops rescheduling" do
    @delivery.update!(attempt_count: WebhookDelivery::MAX_ATTEMPTS - 1)
    with_poster { |**| server_error }

    assert_no_enqueued_jobs only: Outbound::DeliveryJob do
      Outbound::DeliveryJob.perform_now(@delivery.id)
    end

    @delivery.reload
    assert_equal "dead", @delivery.status
    assert_equal WebhookDelivery::MAX_ATTEMPTS, @delivery.attempt_count
  end

  test "an already-delivered delivery is a no-op (no second POST)" do
    @delivery.update!(status: "delivered")
    with_poster { |**| raise "HTTP must not be called" }
    Outbound::DeliveryJob.perform_now(@delivery.id)

    assert_equal "delivered", @delivery.reload.status
  end

  test "signs the body with the subscription secret over timestamp.body" do
    captured = nil
    with_poster { |**kwargs| captured = kwargs; ok }
    Outbound::DeliveryJob.perform_now(@delivery.id)

    timestamp = captured[:headers]["X-Governauthzer-Timestamp"]
    expected = Outbound::Signer.signature(secret: @sub.signing_secret, timestamp: timestamp.to_i, body: captured[:body])
    assert_equal expected, captured[:headers]["X-Governauthzer-Signature"]
    assert_equal "application/cloudevents+json; charset=utf-8", captured[:headers]["Content-Type"]
  end
end
