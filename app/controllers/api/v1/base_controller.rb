class Api::V1::BaseController < ActionController::API
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
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
