module Accesses
  # Requester cancels their own pending request. Emit-before-destroy `access.withdrawn`,
  # then destroy the row (same rationale as denial). Authorized via
  # AccessPolicy#withdraw? by the caller.
  class Withdrawer < ApplicationService
    def initialize(access:, actor:)
      @access = access
      @actor = actor
    end

    def call
      return failure(:not_pending) unless @access.pending?

      ActiveRecord::Base.transaction do
        AuditEvent.record!(
          event_type: "access.withdrawn",
          actor: @actor,
          targets: [ @access.user, @access, @access.role ],
          metadata: { "source" => "web-ui", "via" => "self_withdraw" }
        )
        @access.destroy!
        success(@access)
      end
    end
  end
end
