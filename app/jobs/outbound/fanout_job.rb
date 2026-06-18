module Outbound
  # Projects one committed AuditEvent into outbound deliveries. Enqueued by the
  # AuditEvent after_create_commit hook only for published types, so it runs only
  # for events that can fan out. Builds the CloudEvent once, then for every active
  # subscription whose filters match, creates a (byte-stable) WebhookDelivery and
  # enqueues its DeliveryJob. The unique (subscription, audit_event) index makes
  # this idempotent — a re-run creates no duplicates and re-enqueues nothing.
  class FanoutJob < ApplicationJob
    queue_as :default

    def perform(audit_event_id)
      audit_event = AuditEvent.find_by(id: audit_event_id)
      return if audit_event.nil?

      cloud_event = CloudEventBuilder.new(audit_event).build
      return if cloud_event.nil? # unpublished type / self-app / missing records

      application_id = cloud_event.dig("data", "application", "id")
      matched = false

      WebhookSubscription.active.find_each do |subscription|
        next unless subscription.matches?(cloud_event_type: cloud_event["type"], application_id: application_id)

        matched = true
        delivery = WebhookDelivery.find_or_create_by!(
          webhook_subscription: subscription, audit_event_id: audit_event.id
        ) do |d|
          d.cloud_event_type = cloud_event["type"]
          d.payload = cloud_event
        end

        DeliveryJob.perform_later(delivery.id) if delivery.previously_new_record?
      end

      mark_provisioning_pending(cloud_event) if matched
    end

    private

    # Once a grant has actually been sent to a provisioner, the access moves from
    # not_required → pending (awaiting the reconciliation callback). Only grants
    # (the access row still exists); a revoke destroyed it.
    def mark_provisioning_pending(cloud_event)
      return unless cloud_event["type"] == CloudEventBuilder::TYPE_MAP["access.approved"]

      access = Access.find_by(id: cloud_event.dig("data", "access_id"))
      return if access.nil? || access.provisioning_status != "not_required"

      access.update!(provisioning_status: "pending")
    end
  end
end
