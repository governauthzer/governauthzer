class Api::V1::WhoamiController < Api::V1::BaseController
  # "Who am I" is available to any authenticated token, including reconcile-scoped.
  skip_before_action :require_full_access!

  def show
    render json: {
      token_id:   current_api_token.id,
      token_name: current_api_token.name,
      expires_at: current_api_token.expires_at&.iso8601
    }
  end
end
