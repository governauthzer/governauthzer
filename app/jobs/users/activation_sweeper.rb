module Users
  # Recurring job (hourly) that activates users whose future start_date has arrived:
  # any `pending_start` user with `start_date <= today` transitions to `active` so
  # they can finally authenticate (the `active?` login gate blocks pending_start).
  # Mirrors compute_initial_status, which only runs on create. System actor; no
  # session_version bump (activation enables access, it doesn't freeze a session).
  # Birthright role grants on activation are a Phase-7 concern, not wired here.
  class ActivationSweeper < ApplicationJob
    queue_as :default

    def perform
      User.where(status: "pending_start")
          .where(start_date: ..Date.current)
          .find_each { |user| activate(user) }
    end

    private

    def activate(user)
      ActiveRecord::Base.transaction do
        user.update!(status: "active")
        AuditEvent.record!(
          event_type: "user.status_changed",
          actor: :system,
          targets: user,
          attribute_changes: { "status" => [ "pending_start", "active" ] },
          metadata: {
            "source" => "job",
            "via" => "activation_sweeper",
            "reason" => "start_date_reached"
          }
        )
      end
    end
  end
end
