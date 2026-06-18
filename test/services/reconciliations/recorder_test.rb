require "test_helper"

class Reconciliations::RecorderTest < ActiveSupport::TestCase
  def setup
    Current.correlation_id = SecureRandom.uuid
    @app = Application.create!(name: "Slack", slug: "slack")
    @role = Role.create!(application: @app, name: "Member", slug: "member")
    @user = User.create!(email: "ada@example.com", name: "Ada")
    @access = Access.create!(user: @user, role: @role, status: "approved", provisioning_status: "pending")
    @token = ApiToken.create!(name: "bridge", scope: "reconcile",
                              token_digest: ApiToken.digest(ApiToken.generate_raw_token))
  end

  def approved_event
    AuditEvent.record!(event_type: "access.approved", actor: :system,
                       targets: [ @user, @access, @role ], metadata: {})
  end

  def record(event_id:, status: "applied")
    Reconciliations::Recorder.call(application: @app, event_id: event_id, status: status, api_token: @token)
  end

  test "applied report stamps the access and writes an audit event" do
    event = approved_event
    result = nil
    assert_difference("AuditEvent.where(event_type: 'access.provisioning_reported').count", 1) do
      result = record(event_id: event.id, status: "applied")
    end
    assert result.success
    assert_equal "applied", @access.reload.provisioning_status
    assert result.value[:access_present]
  end

  test "failed report stamps failed" do
    event = approved_event
    assert record(event_id: event.id, status: "failed").success
    assert_equal "failed", @access.reload.provisioning_status
  end

  test "a revoke report (access row gone) is recorded in audit, access_present false" do
    event = AuditEvent.record!(event_type: "access.revoked", actor: :system,
                               targets: [ @user, @access, @role ], metadata: { "reason" => "grant_expired" })
    @access.destroy!
    result = nil
    assert_difference("AuditEvent.where(event_type: 'access.provisioning_reported').count", 1) do
      result = record(event_id: event.id, status: "applied")
    end
    assert result.success
    assert_not result.value[:access_present]
  end

  test "rejects an invalid status" do
    assert_equal :invalid_status, record(event_id: approved_event.id, status: "weird").code
  end

  test "rejects a malformed or unknown event id" do
    assert_equal :unknown_event, record(event_id: "not-a-uuid").code
    assert_equal :unknown_event, record(event_id: SecureRandom.uuid).code
  end

  test "rejects a non-published event type" do
    login = AuditEvent.record!(event_type: "auth.login.succeeded", actor: @user, targets: [ @user ])
    assert_equal :unknown_event, record(event_id: login.id).code
  end

  test "rejects an event belonging to a different application" do
    other_app = Application.create!(name: "AWS", slug: "aws")
    other_role = Role.create!(application: other_app, name: "Admin", slug: "admin")
    other_access = Access.create!(user: @user, role: other_role, status: "approved")
    event = AuditEvent.record!(event_type: "access.approved", actor: :system,
                               targets: [ @user, other_access, other_role ], metadata: {})
    assert_equal :event_application_mismatch, record(event_id: event.id).code
  end
end
