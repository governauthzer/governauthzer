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
      ActiveRecord::Base.transaction do
        # The third party to the approval race: withdrawing pulls the row out from
        # under an approver mid-decision. Take the same lock so one of the two wins
        # cleanly instead of the loser hitting a foreign-key violation.
        @access.lock!
        next failure(:not_pending) unless @access.pending?

        AuditEvent.record!(
          event_type: "access.withdrawn",
          actor: @actor,
          targets: [ @access.user, @access, @access.role ],
          metadata: { "source" => "web-ui", "via" => "self_withdraw" }
        )
        @access.destroy!
        success(@access)
      end
    rescue ActiveRecord::RecordNotFound
      failure(:no_longer_exists)
    end
  end
end
