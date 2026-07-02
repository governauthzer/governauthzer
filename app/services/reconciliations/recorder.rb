module Reconciliations
  # Records a provisioner's reconciliation report for one previously-emitted
  # outbound event. The bridge echoes the CloudEvent `id` (= AuditEvent.id) it
  # applied, plus applied/failed and an optional detail. We resolve the event to
  # its access and, if the access still exists (grants do; revokes destroyed the
  # row), stamp its provisioning_status. Either way we write an
  # `access.provisioning_reported` audit event — so a revoke report (no access
  # row) still leaves a durable trace.
  class Recorder < ApplicationService
    REPORTABLE_STATUSES = %w[applied failed].freeze
    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    def initialize(application:, event_id:, status:, api_token:, detail: nil)
      @application = application
      @event_id = event_id
      @status = status
      @api_token = api_token
      @detail = detail
    end

    def call
      return failure(:invalid_status) unless REPORTABLE_STATUSES.include?(@status)
      return failure(:unknown_event) unless @event_id.match?(UUID_FORMAT)

      event = AuditEvent.find_by(id: @event_id)
      return failure(:unknown_event) if event.nil?
      return failure(:unknown_event) unless Outbound::CloudEventBuilder.publishable_type?(event.event_type)

      role = Role.find_by(id: event.target_id("Role"))
      return failure(:event_application_mismatch) if role.nil? || role.application_id != @application.id

      access = Access.find_by(id: event.target_id("Access"))

      ActiveRecord::Base.transaction do
        access&.update!(provisioning_status: @status)
        AuditEvent.record!(
          event_type: "access.provisioning_reported",
          actor: :system,
          targets: [ access, role ].compact,
          metadata: {
            "source" => "api",
            "via" => "reconciliation",
            "provisioning_status" => @status,
            "event_id" => @event_id,
            "detail" => @detail,
            "api_token_id" => @api_token.id,
            "api_token_name" => @api_token.name
          }.compact
        )
      end

      success(event_id: @event_id, provisioning_status: @status, access_present: access.present?)
    end
  end
end
