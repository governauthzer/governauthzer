class Api::V1::BaseController < ActionController::API
  # Include order matters: ErrorRendering provides render_error, which Sorting's
  # rescue handler calls. Pagination is independent. Don't reorder without
  # checking what each concern depends on at include-time.
  include Api::ErrorRendering
  include Api::Pagination
  include Api::Sorting

  before_action :authenticate_api_token!

  attr_reader :current_api_token

  private

  def authenticate_api_token!
    header = request.authorization.to_s
    if header.start_with?("Bearer ")
      raw = header.sub(/\ABearer\s+/, "").strip
      token = ApiToken.find_by_raw_token(raw)
      if token&.redeemable?
        @current_api_token = token
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
