require "test_helper"

class Users::ActivationSweeperTest < ActiveJob::TestCase
  test "activates pending_start users whose start_date has arrived, leaves future ones" do
    # Created with a future start_date → pending_start, then the date "arrives"
    # (update_column bypasses compute_initial_status, which only runs on create).
    arrived = User.create!(email: "arrived@example.com", name: "Arrived", start_date: 1.month.from_now)
    arrived.update_column(:start_date, 1.day.ago)
    future = User.create!(email: "future@example.com", name: "Future", start_date: 1.month.from_now)

    assert_equal "pending_start", arrived.reload.status
    assert_difference("AuditEvent.where(event_type: 'user.status_changed').count", 1) do
      Users::ActivationSweeper.perform_now
    end

    assert_equal "active", arrived.reload.status
    assert_equal "pending_start", future.reload.status
  end
end
