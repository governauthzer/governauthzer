# Shared emit-before-destroy access revocation, used by both the orphan cascade
# (snapshot drop) and direct termination. Per the 2026-05-13 Access lock a revoke
# destroys the row (no `revoked` status); per the audit-log lock `access.revoked`
# is emit-before-destroy so the target snapshot survives the row deletion. Only
# approved accesses emit (a pending request silently disappearing isn't a grant
# being revoked). Mix into a service that runs inside a transaction.
module AccessRevocation
  private

  def revoke_all_accesses(user:, actor:, source:, via:, reason:)
    user.accesses.includes(:role).each do |access|
      if access.approved?
        AuditEvent.record!(
          event_type: "access.revoked",
          actor: actor,
          targets: [ user, access, access.role ],
          metadata: { "source" => source, "via" => via, "reason" => reason }
        )
      end
      access.destroy!
    end
  end
end
