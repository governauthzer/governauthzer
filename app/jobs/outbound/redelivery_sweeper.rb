module Outbound
  # Recurring safety net (every 15 min) for webhook deliveries whose retry job
  # was lost. DeliveryJob's self-re-enqueue is the primary retry path, but the
  # failure row update and the re-enqueue are not atomic (a worker dying between
  # them strands the row), and the queue lives in its own database (purging or
  # restoring it drops scheduled retries while delivery rows survive). This job
  # re-enqueues anything stuck past the grace window. Double-enqueue is harmless:
  # DeliveryJob is idempotent per row (delivered?/dead? guards) and the outbound
  # contract is at-least-once. Dead rows are not retried — they exhausted
  # MAX_ATTEMPTS and await operator attention.
  class RedeliverySweeper < ApplicationJob
    queue_as :default

    GRACE = 10.minutes

    def perform
      WebhookDelivery.stuck(grace: GRACE).find_each do |delivery|
        DeliveryJob.perform_later(delivery.id)
      end
    end
  end
end
