module Sync
  # Shared cascade for a user that has lost its last identity (snapshot drop) —
  # the same mechanical path Phase 4 termination will reuse with a different
  # trigger. Caller is responsible for the surrounding transaction.
  #
  # Note: the status flip to `orphaned` alone freezes admin-UI sessions, because
  # ApplicationController#resolve_current_user rejects any non-active user. The
  # session_version bump is the forward-looking hook for the broader
  # invalidate-on-role-change invariant (Phase 6), not load-bearing here yet.
  class OrphanedCascade < ApplicationService
    def initialize(user:, actor:, via:, reason: "user_orphaned")
      @user = user
      @actor = actor
      @via = via
      @reason = reason
    end

    def call
      revoke_accesses
      orphan_user
      success(@user)
    end

    private

    def revoke_accesses
      @user.accesses.includes(:role).each do |access|
        # emit-before-destroy so the target snapshot survives the row deletion
        # (audit-log lock 2026-05-20: access.revoked is emit-before-destroy).
        if access.approved?
          AuditEvent.record!(
            event_type: "access.revoked",
            actor: @actor,
            targets: [ @user, access, access.role ],
            metadata: { "reason" => @reason, "via" => @via }
          )
        end
        access.destroy!
      end
    end

    def orphan_user
      prior_status = @user.status
      @user.update!(status: "orphaned", orphaned_at: Time.current)
      @user.increment!(:session_version)
      AuditEvent.record!(
        event_type: "user.orphaned",
        actor: @actor,
        targets: @user,
        metadata: { "prior_status" => prior_status, "via" => @via }
      )
    end
  end
end
