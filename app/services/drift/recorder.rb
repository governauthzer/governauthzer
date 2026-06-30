module Drift
  # Records a fulfilment bridge's drift sweep into the audit log. Drift is the
  # divergence between core's intent (active grants) and a target's actual state
  # (e.g. someone edited a Google Workspace group out of band).
  #
  # This is audit-only by design (decision 2026-06-30): we write ONE
  # `provisioning.drift_detected` audit event per sweep with the full findings in
  # metadata — we do NOT touch any Access state. The bridge only reports when it
  # found drift, and core never polls the target itself (decision-plane intact).
  #
  # Unlike reconciliation this is not keyed on an event_id: drift has no
  # originating outbound event, it's a periodic observation.
  class Recorder < ApplicationService
    def initialize(api_token:, params:)
      @api_token = api_token
      @params = params || {}
    end

    def call
      reports = Array(@params[:reports])
      return failure(:invalid_drift_report) if reports.empty?
      return failure(:invalid_drift_report) unless reports.all? { |r| valid_entry?(r) }

      groups = reports.map { |r| group_summary(r) }
      missing_total = groups.sum { |g| g["missing_count"] }
      extra_total = groups.sum { |g| g["extra_count"] }

      audit = AuditEvent.record!(
        event_type: "provisioning.drift_detected",
        actor: :system,
        targets: [],
        metadata: {
          "source" => "api",
          "via" => "drift_reconciliation",
          "observed_at" => @params[:observed_at].presence,
          "group_count" => groups.size,
          "missing_total" => missing_total,
          "extra_total" => extra_total,
          "groups" => groups,
          "api_token_id" => @api_token.id,
          "api_token_name" => @api_token.name
        }.compact
      )

      success(
        recorded: true,
        group_count: groups.size,
        missing_total: missing_total,
        extra_total: extra_total,
        audit_event_id: audit.id
      )
    end

    private

    def valid_entry?(report)
      report[:application_slug].present? && report[:role_slug].present?
    end

    def group_summary(report)
      missing = Array(report[:missing])
      extra = Array(report[:extra])
      {
        "application_slug" => report[:application_slug],
        "role_slug" => report[:role_slug],
        "missing" => missing.map { |m| { "user_id" => m[:user_id], "email" => m[:email] }.compact },
        "extra" => extra.map { |e| { "email" => e[:email] } },
        "missing_count" => missing.size,
        "extra_count" => extra.size
      }
    end
  end
end
