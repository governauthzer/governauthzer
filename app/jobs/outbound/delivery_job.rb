module Outbound
  # Delivers one WebhookDelivery: signs the frozen CloudEvent payload (byte-stable
  # across retries → stable id + signature) and POSTs it in CloudEvents structured
  # mode. On a transient failure (non-2xx or network error) it records the failure
  # on the row and self-reschedules with exponential backoff until MAX_ATTEMPTS,
  # then marks the row `dead`. Delivery state lives on the row for operator
  # visibility, so retries are tracked explicitly rather than via ActiveJob's
  # retry_on (which would double-count).
  class DeliveryJob < ApplicationJob
    queue_as :default

    # Swappable transport (defaults to the real Net::HTTP poster). A seam so the
    # job can be driven in tests without a network or a webmock dependency.
    class_attribute :http_poster, default: HttpPoster

    def perform(delivery_id)
      delivery = WebhookDelivery.find_by(id: delivery_id)
      return if delivery.nil? || delivery.delivered? || delivery.dead?

      body = JSON.generate(delivery.payload)
      timestamp = Time.current.to_i
      subscription = delivery.webhook_subscription

      response = http_poster.post(
        url: subscription.endpoint_url,
        body: body,
        headers: {
          "Content-Type" => "application/cloudevents+json; charset=utf-8",
          "X-Governauthzer-Event-Id" => delivery.audit_event_id,
          "X-Governauthzer-Timestamp" => timestamp.to_s,
          "X-Governauthzer-Signature" => Signer.signature(secret: subscription.signing_secret, timestamp: timestamp, body: body)
        }
      )

      if (200..299).cover?(response.code)
        delivery.update!(status: "delivered", delivered_at: Time.current,
                         attempt_count: delivery.attempt_count + 1,
                         last_response_code: response.code, last_error: nil)
      else
        record_failure(delivery, error: "HTTP #{response.code}", code: response.code)
      end
    rescue StandardError => e
      record_failure(delivery, error: e.message, code: nil) if delivery
    end

    private

    def record_failure(delivery, error:, code:)
      delivery.attempt_count += 1
      if delivery.attempt_count >= WebhookDelivery::MAX_ATTEMPTS
        delivery.update!(status: "dead", last_response_code: code, last_error: error)
      else
        delivery.update!(status: "failed", last_response_code: code, last_error: error,
                         next_retry_at: Time.current + delivery.backoff_delay)
        self.class.set(wait: delivery.backoff_delay).perform_later(delivery.id)
      end
    end
  end
end
