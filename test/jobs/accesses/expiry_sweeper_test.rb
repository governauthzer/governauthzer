require "test_helper"

class Accesses::ExpirySweeperTest < ActiveJob::TestCase
  def setup
    @app = Application.create!(name: "Slack", slug: "slack")
    @alice = users(:alice)
  end

  test "revokes approved grants past expires_at and leaves live or permanent ones" do
    expired   = grant("slack-user",  expires_at: 1.hour.ago)
    live      = grant("slack-admin", expires_at: 1.day.from_now)
    permanent = grant("slack-guest", expires_at: nil)

    assert_difference("AuditEvent.where(event_type: 'access.revoked').count", 1) do
      Accesses::ExpirySweeper.perform_now
    end

    assert_not Access.exists?(expired.id), "expired grant should be revoked"
    assert Access.exists?(live.id), "live grant should survive"
    assert Access.exists?(permanent.id), "permanent grant should survive"
  end

  test "ignores a pending grant past its expiry (expiry applies to granted access only)" do
    Access.create!(user: @alice, role: role("slack-user"), status: "pending",
                   source: "self_request", expires_at: 1.hour.ago)

    assert_no_difference([ "AuditEvent.where(event_type: 'access.revoked').count", "Access.count" ]) do
      Accesses::ExpirySweeper.perform_now
    end
  end

  private

  def role(slug)
    Role.create!(application: @app, name: slug.titleize, slug: slug)
  end

  def grant(slug, expires_at:)
    Access.create!(user: @alice, role: role(slug), status: "approved", source: "manual", expires_at: expires_at)
  end
end
