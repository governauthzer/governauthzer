require "test_helper"

class Sync::OrphanedSweeperTest < ActiveJob::TestCase
  test "terminates orphans past the grace period, leaves fresh ones" do
    expired = User.create!(email: "expired@example.com", name: "Expired", status: "orphaned", orphaned_at: 80.hours.ago)
    fresh   = User.create!(email: "fresh@example.com", name: "Fresh", status: "orphaned", orphaned_at: 1.hour.ago)

    assert_difference("AuditEvent.where(event_type: 'user.status_changed').count", 1) do
      Sync::OrphanedSweeper.perform_now
    end

    assert_equal "terminated", expired.reload.status
    assert_nil expired.orphaned_at
    assert_equal "orphaned", fresh.reload.status
  end
end
