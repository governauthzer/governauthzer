module Api
  module V1
    # A fulfilment bridge reports an out-of-band drift sweep (target membership
    # diverged from core's intent) so it lands in the tamper-proof audit log.
    # Accepts a reconcile-scoped token (the bridge's token) or full. Audit-only:
    # one `provisioning.drift_detected` event per sweep; no Access state changes.
    class DriftReportsController < Api::V1::BaseController
      skip_before_action :require_full_access!

      # POST /api/v1/drift-reports
      def create
        result = Drift::Recorder.call(api_token: current_api_token, params: drift_params)

        if result.success
          render json: serialize(result.value), status: :ok
        else
          render_service_failure(result)
        end
      end

      private

      def drift_params
        params.permit(
          :observed_at,
          reports: [
            :application_slug, :role_slug,
            { missing: [ :user_id, :email ], extra: [ :email ] }
          ]
        ).to_h.deep_symbolize_keys
      end

      def serialize(value)
        {
          "recorded" => value[:recorded],
          "group_count" => value[:group_count],
          "missing_total" => value[:missing_total],
          "extra_total" => value[:extra_total],
          "audit_event_id" => value[:audit_event_id]
        }
      end
    end
  end
end
