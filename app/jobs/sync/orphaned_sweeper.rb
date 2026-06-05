module Sync
  # Recurring job (hourly) that expires the orphan grace period: any user that has
  # sat in `orphaned` for longer than GRACE is transitioned to `terminated`.
  # Accesses were already revoked at orphan time, so there is no further cascade.
  class OrphanedSweeper < ApplicationJob
    queue_as :default

    GRACE = 72.hours

    def perform
      User.where(status: "orphaned")
          .where(orphaned_at: ..GRACE.ago)
          .find_each { |user| terminate(user) }
    end

    private

    def terminate(user)
      ActiveRecord::Base.transaction do
        prior_orphaned_at = user.orphaned_at
        user.update!(status: "terminated", orphaned_at: nil)
        AuditEvent.record!(
          event_type: "user.status_changed",
          actor: :system,
          targets: user,
          attribute_changes: { "status" => [ "orphaned", "terminated" ] },
          metadata: {
            "via" => "orphaned_sweeper",
            "reason" => "orphan_grace_expired",
            "orphaned_at" => prior_orphaned_at&.iso8601
          }
        )
      end
    end
  end
end
