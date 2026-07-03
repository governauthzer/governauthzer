module Api
  module V1
    # Bulk read of active grants — "who should hold which role" — so a fulfilment
    # bridge can reconcile the target system against core (drift detection).
    #
    # Core is the source of truth: a bridge pulls this fresh and never caches it.
    # Accepts a reconcile-scoped token (the bridge's token) or a full token.
    #
    # The unit is the grant (a user holds a role); `application.slug` only
    # namespaces the role (role slugs are unique per application — same coordinates
    # the outbound CloudEvent carries). The self/operator application is excluded:
    # its grants are never provisioned externally.
    class GrantsController < Api::V1::BaseController
      skip_before_action :require_full_access!

      # GET /api/v1/grants
      def index
        render json: Api::V1::GrantSerializer.collection(paginate(grants_scope))
      end

      private

      def grants_scope
        scope = Access.approved
                      .includes(:user, role: :application)
                      .order(:created_at, :id)

        self_app_id = Application.self_app&.id
        scope = scope.where(role: Role.where.not(application_id: self_app_id)) if self_app_id
        scope
      end
    end
  end
end
