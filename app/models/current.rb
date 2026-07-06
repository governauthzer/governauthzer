class Current < ActiveSupport::CurrentAttributes
  # api_token is set by Api::V1::BaseController after Bearer auth so every audit
  # event emitted anywhere in the request (services, cascades) is attributable to
  # the consumer — AuditEvent.record! stamps it into metadata.
  attribute :correlation_id, :ip_address, :user_agent, :api_token
end
