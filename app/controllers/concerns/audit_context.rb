module AuditContext
  extend ActiveSupport::Concern

  included do
    before_action :set_audit_context
  end

  private

  def set_audit_context
    Current.correlation_id = SecureRandom.uuid
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
  end
end
