class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  include AuditContext

  helper_method :current_user, :signed_in?, :policy_for

  def policy_for(record)
    klass = "#{record.class.name}Policy".constantize
    klass.new(user: current_user, record: record)
  end

  private

  def require_login!
    redirect_to login_path unless signed_in?
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
      value: { "user_id" => user.id, "session_version" => user.session_version },
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
    # The session cookie is a 24h bearer token; carrying session_version makes it
    # revocable. A mismatch means the user's sessions were invalidated since this
    # cookie was issued (e.g. suspend/terminate/orphan bumps it) — reject it.
    # Old-shape cookies without the field (session_version nil) fail this and force
    # a fresh login. Authorization itself is computed live from the DB every request
    # (active?, operator?, policies), so this is about killing stale cookies, not
    # about reflecting access changes — those are already live.
    return nil unless payload["session_version"] == user.session_version
    user
  end
end
