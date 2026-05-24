class Api::V1::WhoamiController < Api::V1::BaseController
  def show
    render json: {
      token_id:   current_api_token.id,
      token_name: current_api_token.name,
      expires_at: current_api_token.expires_at&.iso8601
    }
  end
end
