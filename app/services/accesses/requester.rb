module Accesses
  # Creates a pending access request that enters the role's approval workflow
  # (workflow-only grant model — there is no direct manual grant in v1). The
  # requester is always the subject themselves (self-request via the end-user UI);
  # `manager_of_requester` therefore routes to the subject's own manager.
  #
  # Edge cases at creation time, evaluated on an unsaved Access so we never persist
  # a stuck request:
  #   - zero-step workflow → fully_approved? immediately → granted on the spot.
  #   - steps exist but no eligible approver resolves → failure(:no_eligible_approver).
  class Requester < ApplicationService
    def initialize(user:, role:, actor:, justification: nil, expires_at: nil)
      @user = user
      @role = role
      @actor = actor
      @justification = justification
      @expires_at = expires_at
    end

    def call
      return failure(:access_already_exists) if Access.exists?(user: @user, role: @role)

      access = Access.new(
        user: @user, role: @role, requested_by: @user,
        source: "self_request", status: "pending",
        justification: @justification, expires_at: @expires_at
      )

      return failure(:no_eligible_approver) if unroutable?(access)

      ActiveRecord::Base.transaction do
        access.save!
        access.fully_approved? ? grant(access) : announce_request(access)
        success(access)
      end
    end

    private

    # No one can act on this request: a step exists but resolves no approver, or the
    # role points at the default workflow and none is configured (find_by! raises).
    def unroutable?(access)
      !access.fully_approved? && access.current_approver.nil?
    rescue ActiveRecord::RecordNotFound
      true
    end

    def grant(access)
      access.update!(status: "approved")
      AuditEvent.record!(
        event_type: "access.approved",
        actor: @actor,
        targets: [ access.user, access, access.role ],
        justification: @justification,
        metadata: { "source" => "admin-ui", "via" => "self_request", "decision_method" => "workflow" }
      )
    end

    def announce_request(access)
      AuditEvent.record!(
        event_type: "access.requested",
        actor: @actor,
        targets: [ access.user, access, access.role ],
        justification: @justification,
        metadata: { "source" => "admin-ui", "via" => "self_request" }
      )
    end
  end
end
