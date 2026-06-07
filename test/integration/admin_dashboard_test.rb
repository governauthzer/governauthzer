require "test_helper"

class AdminDashboardTest < ActionDispatch::IntegrationTest
  def setup
    @self_app = Application.create!(name: "Governauthzer", slug: Application::SELF_SLUG)
    operator_role = @self_app.roles.create!(name: "Operator", slug: "operator", protected: true)
    @operator = User.create!(email: "op@example.com", name: "Op")
    Access.create!(user: @operator, role: operator_role, status: "approved", source: "manual")
    sign_in_as @operator
  end

  test "admin root renders the dashboard with overview counts" do
    app = Application.create!(name: "Slack", slug: "slack")
    role = app.roles.create!(name: "Member", slug: "member")
    requester = User.create!(email: "req@example.com", name: "Req")
    Access.create!(user: requester, role: role, status: "pending", source: "self_request")

    get "/admin"
    assert_response :ok
    assert_includes response.body, "Dashboard"
    assert_includes response.body, "Pending approvals"
    assert_includes response.body, "Users by status"
    assert_includes response.body, "Recent activity"
  end

  test "recent activity surfaces audit events" do
    AuditEvent.create!(occurred_at: Time.current, schema_version: "1.0",
                       event_type: "application.created", actor_type: "user",
                       actor_id: @operator.id, actor_display: "Op",
                       correlation_id: SecureRandom.uuid, metadata: { "source" => "admin-ui" })
    get "/admin"
    assert_response :ok
    assert_includes response.body, "application.created"
  end

  test "a non-operator is forbidden" do
    plain = User.create!(email: "plain@example.com", name: "Plain")
    sign_in_as plain
    get "/admin"
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
