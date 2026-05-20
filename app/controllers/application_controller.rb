class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_audit_context

  private

  def set_audit_context
    Current.correlation_id = SecureRandom.uuid
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end
end
