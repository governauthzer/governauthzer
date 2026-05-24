class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_audit_context

  helper_method :current_user, :signed_in?

  private

  def set_audit_context
    Current.correlation_id = SecureRandom.uuid
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = resolve_current_user
  end

  def signed_in?
    current_user.present?
  end

  def sign_in(user)
    cookies.signed[:session] = {
      value: { "user_id" => user.id },
      expires: 24.hours.from_now,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }
    @current_user = user
  end

  def sign_out
    cookies.delete(:session)
    @current_user = nil
  end

  def resolve_current_user
    payload = cookies.signed[:session]
    return nil unless payload.is_a?(Hash)
    user = User.find_by(id: payload["user_id"])
    return nil unless user&.active?
    user
  end
end
