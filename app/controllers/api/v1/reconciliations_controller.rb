module Api
  module V1
    # Provisioner → core feedback: the bridge reports whether it applied an
    # outbound event. Accepts a reconcile-scoped token (or full) — the only
    # endpoint a bridge/handler token can reach.
    class ReconciliationsController < Api::V1::BaseController
      skip_before_action :require_full_access!

      # POST /api/v1/applications/:application_id/reconciliations
      def create
        application = find_application
        return if application.nil?

        result = Reconciliations::Recorder.call(
          application: application,
          event_id: reconciliation_params[:event_id].to_s,
          status: reconciliation_params[:status].to_s,
          detail: reconciliation_params[:detail],
          api_token: current_api_token
        )

        if result.success
          render json: serialize(result.value), status: :ok
        else
          render_service_failure(result)
        end
      end

      private

      def find_application
        id = params[:application_id].to_s
        application = Application.find_by(id: id) if id.match?(Reconciliations::Recorder::UUID_FORMAT)
        return application if application

        render_error(code: "not_found", status: :not_found, message: "Application not found.")
        nil
      end

      def reconciliation_params
        params.permit(:event_id, :status, :detail)
      end

      def serialize(value)
        {
          "event_id" => value[:event_id],
          "provisioning_status" => value[:provisioning_status],
          "access_present" => value[:access_present]
        }
      end
    end
  end
end
