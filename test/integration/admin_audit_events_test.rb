require "test_helper"

class AdminAuditEventsTest < ActionDispatch::IntegrationTest
  def setup
    self_app = Application.create!(name: "Governauthzer", slug: Application::SELF_SLUG)
    operator_role = self_app.roles.create!(name: "Operator", slug: "operator", protected: true)
    @operator = User.create!(email: "op@example.com", name: "Op")
    Access.create!(user: @operator, role: operator_role, status: "approved", source: "manual")
    @target = User.create!(email: "target@example.com", name: "Target")
    @corr = SecureRandom.uuid

    AuditEvent.create!(occurred_at: 3.hours.ago, schema_version: "1.0", event_type: "user.created",
                       actor_type: "system", correlation_id: SecureRandom.uuid,
                       targets: [ { "type" => "User", "id" => @target.id, "display" => "Target" } ],
                       metadata: { "source" => "api" })
    AuditEvent.create!(occurred_at: 2.hours.ago, schema_version: "1.0", event_type: "access.approved",
                       actor_type: "user", actor_id: @operator.id, actor_display: "Op", correlation_id: @corr)
    AuditEvent.create!(occurred_at: 1.hour.ago, schema_version: "1.0", event_type: "user.updated",
                       actor_type: "user", actor_id: @operator.id, actor_display: "Op", correlation_id: @corr,
                       attribute_changes: { "status" => [ "active", "suspended" ] })

    sign_in_as @operator
  end

  test "index lists all events" do
    get "/admin/audit_events"
    assert_response :ok
    assert_includes response.body, "user.created"
    assert_includes response.body, "access.approved"
  end

  test "filter by event_type narrows results" do
    get "/admin/audit_events", params: { event_type: "user.created" }
    assert_response :ok
    assert_includes response.body, "1 event"
  end

  test "filter by correlation_id groups one logical operation" do
    get "/admin/audit_events", params: { correlation_id: @corr }
    assert_response :ok
    assert_includes response.body, "2 events"
  end

  test "filter by target returns events touching that record" do
    get "/admin/audit_events", params: { target_type: "User", target_id: @target.id }
    assert_response :ok
    assert_includes response.body, "1 event"
  end

  test "an invalid correlation_id filter is ignored, not an error" do
    get "/admin/audit_events", params: { correlation_id: "not-a-uuid" }
    assert_response :ok
    assert_includes response.body, "user.created", "filter ignored → all events still shown"
  end

  test "detail shows attribute changes" do
    event = AuditEvent.find_by!(event_type: "user.updated")
    get "/admin/audit_events/#{event.id}"
    assert_response :ok
    assert_includes response.body, "status"
    assert_includes response.body, "suspended"
  end

  test "a non-operator is forbidden" do
    plain = User.create!(email: "plain@example.com", name: "Plain")
    sign_in_as plain
    get "/admin/audit_events"
    assert_response :forbidden
  end

  private

  def sign_in_as(user)
    raw = SecureRandom.urlsafe_base64(32)
    EmergencyToken.create!(user: user, token_digest: EmergencyToken.digest(raw),
                           reason: "test sign-in", expires_at: 5.minutes.from_now)
    get "/emergency-login/#{raw}"
  end
end
