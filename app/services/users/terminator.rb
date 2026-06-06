module Users
  # Direct termination of an active / suspended / pending_start user: revokes all
  # accesses (emit-before-destroy) then flips status to `terminated` and emits
  # `user.terminated`. Identities are deliberately NOT touched — the `active?` gate
  # in ApplicationController#resolve_current_user already blocks login for any
  # non-active user, so "locking" identities would add no security (same reasoning
  # as OrphanedCascade). The session_version bump is the forward-looking hook for
  # the invalidate-on-role-change invariant (Phase 6), consistent with the orphan
  # cascade.
  #
  # This is the only explicit-terminate entry point: snapshots reject an inbound
  # `status: terminated` (Sync::Snapshots::Validate#check_users), and the
  # orphaned→terminated grace-expiry path lives in Sync::OrphanedSweeper (no
  # cascade there — accesses were already revoked at orphan time). Caller is
  # responsible for the surrounding transaction.
  class Terminator < ApplicationService
    include AccessRevocation

    def initialize(user:, actor:, source:, via:, reason: "user_terminated")
      @user = user
      @actor = actor
      @source = source    # audit channel: "api" (PATCH), future "admin-ui"
      @via = via          # trigger sub-flow: "termination"
      @reason = reason
    end

    def call
      revoke_all_accesses(user: @user, actor: @actor, source: @source, via: @via, reason: @reason)
      terminate_user
      success(@user)
    end

    private

    def terminate_user
      prior_status = @user.status
      @user.update!(status: "terminated")
      @user.increment!(:session_version)
      AuditEvent.record!(
        event_type: "user.terminated",
        actor: @actor,
        targets: @user,
        metadata: { "source" => @source, "via" => @via, "prior_status" => prior_status }
      )
    end
  end
end
