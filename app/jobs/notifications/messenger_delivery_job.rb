module Notifications
  # Posts one notification to the messenger webhook. Best effort, like email: a
  # network error or a 5xx is retried a few times with backoff; a 4xx means the
  # endpoint refused this request (revoked webhook, wrong chat id) and retrying would
  # only repeat it. Every attempt leaves its result on the settings row, which is how
  # the operator learns that the channel has stopped working.
  class MessengerDeliveryJob < ApplicationJob
    queue_as :default

    class TransientFailure < StandardError; end

    ATTEMPTS = 5
    ERROR_BODY_LIMIT = 300

    retry_on TransientFailure, wait: :polynomially_longer, attempts: ATTEMPTS do |_job, error|
      Rails.logger.warn("[messenger] giving up after #{ATTEMPTS} attempts: #{error.message}")
    end

    # Same seam as Outbound::DeliveryJob: Net::HTTP, which never follows redirects —
    # a redirect must not carry the message somewhere the operator did not choose.
    class_attribute :http_poster, default: Outbound::HttpPoster

    # POSTs a rendered body and records the outcome. Network errors propagate.
    def self.deliver(settings, body)
      response = http_poster.post(
        url: settings.messenger_url,
        body: body,
        headers: { "Content-Type" => "application/json; charset=utf-8" }
      )
      if (200..299).cover?(response.code)
        settings.record_messenger_result!(code: response.code, error: nil)
      else
        settings.record_messenger_result!(code: response.code, error: describe(response))
      end
      response
    end

    def self.describe(response)
      "HTTP #{response.code}: #{response.body.to_s.strip}".truncate(ERROR_BODY_LIMIT)
    end

    # vars: the template placeholders, as primitives (see AccessNotifications).
    # Settings are read now, not at enqueue time, so switching the channel off or
    # fixing its URL applies to messages already queued.
    def perform(vars)
      settings = NotificationSetting.current
      return unless settings.persisted? && settings.messenger_enabled? && settings.messenger_configured?

      response = post(settings, settings.render_messenger_body(vars))
      raise TransientFailure, self.class.describe(response) if response.code >= 500
    end

    private

    # Network-level failures share no ancestor (DNS, refused, timeout, TLS), so the
    # rescue is broad — but it wraps only the POST, never the template rendering.
    def post(settings, body)
      self.class.deliver(settings, body)
    rescue StandardError => e
      message = "#{e.class.name}: #{e.message}".truncate(ERROR_BODY_LIMIT)
      settings.record_messenger_result!(code: nil, error: message)
      raise TransientFailure, message
    end
  end
end
