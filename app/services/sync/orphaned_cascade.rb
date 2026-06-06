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
    include AccessRevocation

    def initialize(user:, actor:, source:, via:, reason: "user_orphaned")
      @user = user
      @actor = actor
      @source = source    # audit channel: "api" (snapshot)
      @via = via          # trigger sub-flow: "snapshot"
      @reason = reason
    end

    def call
      revoke_all_accesses(user: @user, actor: @actor, source: @source, via: @via, reason: @reason)
      orphan_user
      success(@user)
    end

    private

    def orphan_user
      prior_status = @user.status
      @user.update!(status: "orphaned", orphaned_at: Time.current)
      @user.increment!(:session_version)
      AuditEvent.record!(
        event_type: "user.orphaned",
        actor: @actor,
        targets: @user,
        metadata: { "source" => @source, "via" => @via, "prior_status" => prior_status }
      )
    end
  end
end
