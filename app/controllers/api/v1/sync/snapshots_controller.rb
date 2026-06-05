module Api
  module V1
    module Sync
      class SnapshotsController < Api::V1::BaseController
        before_action :require_sync_scoped_token!

        # POST /api/v1/sync/snapshots
        # Full-roster snapshot for one source (source derived from the token scope).
        # Absence from `users[]` is the drop signal. See snapshot-sync-design.
        def create
          result = ::Sync::Snapshots::Apply.call(
            api_token: current_api_token,
            params: snapshot_params
          )

          if result.success
            render json: serialize(result.value), status: :ok
          else
            render_service_failure(result)
          end
        end

        private

        def require_sync_scoped_token!
          return if current_api_token.sync_scoped?

          render_error(
            code: "source_scope_required",
            status: :forbidden,
            message: "This token is not scoped to an HRIS source; snapshot sync requires a source-scoped token."
          )
        end

        def snapshot_params
          params.permit(
            :as_of, :expected_count, :dry_run, :override_circuit_breaker,
            users: [
              :external_id, :email, :name, :status, :department, :title,
              :start_date, :end_date, :manager_external_id
            ]
          ).to_h.symbolize_keys
        end

        def serialize(value)
          {
            "source" => value[:source],
            "as_of" => value[:as_of]&.iso8601,
            "applied" => value[:applied],
            "diff" => value[:diff],
            "orphaned" => value[:orphaned],
            "warnings" => value[:warnings],
            "snapshot_run_id" => value[:snapshot_run_id]
          }
        end
      end
    end
  end
end
