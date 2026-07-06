class Api::V1::BaseController < ActionController::API
  include AuditContext

  # Include order matters: ErrorRendering provides render_error, which Sorting's
  # rescue handler calls. Pagination is independent. Don't reorder without
  # checking what each concern depends on at include-time.
  include Api::ErrorRendering
  include Api::Pagination
  include Api::Sorting
  include Api::ServiceFailureRendering

  before_action :authenticate_api_token!
  # Management API is full-scope by default (fail-safe: a new endpoint stays
  # locked down unless it opts out). Endpoints that also accept a reconcile-scoped
  # token (reconciliations, whoami) skip this.
  before_action :require_full_access!

  # The authenticated consumer lives in Current (single source of truth) so audit
  # emission deep in services/cascades can attribute events without kwarg-threading.
  def current_api_token
    Current.api_token
  end

  private

  def require_full_access!
    return if current_api_token.full_access?

    render_error(
      code: "scope_insufficient",
      status: :forbidden,
      message: "This token is scoped to reconciliation only and cannot access the management API."
    )
  end

  def authenticate_api_token!
    header = request.authorization.to_s
    if header.start_with?("Bearer ")
      raw = header.sub(/\ABearer\s+/, "").strip
      token = ApiToken.find_by_raw_token(raw)
      if token&.redeemable?
        Current.api_token = token
        return
      end
    end
    render_error(
      code: "unauthorized",
      status: :unauthorized,
      message: "Missing or invalid API token."
    )
  end
end
