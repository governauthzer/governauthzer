class Current < ActiveSupport::CurrentAttributes
  attribute :correlation_id, :ip_address, :user_agent
end
