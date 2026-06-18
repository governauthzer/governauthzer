require "test_helper"

class Api::V1::ReconciliationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    Current.correlation_id = SecureRandom.uuid
    @application = Application.create!(name: "Slack", slug: "slack")
    @role = Role.create!(application: @application, name: "Member", slug: "member")
    @user = User.create!(email: "ada@example.com", name: "Ada")
    @access = Access.create!(user: @user, role: @role, status: "approved", provisioning_status: "pending")
    @event = AuditEvent.record!(event_type: "access.approved", actor: :system,
                                targets: [ @user, @access, @role ], metadata: {})

    @reconcile_raw = ApiToken.generate_raw_token
    @reconcile_token = ApiToken.create!(name: "bridge", scope: "reconcile",
                                        token_digest: ApiToken.digest(@reconcile_raw))
    @full_raw = ApiToken.generate_raw_token
    @full_token = ApiToken.create!(name: "mgmt", token_digest: ApiToken.digest(@full_raw))
  end

  def post_reconciliation(body, app_id: @application.id, token: @reconcile_raw)
    post "/api/v1/applications/#{app_id}/reconciliations",
         params: body.to_json,
         headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  end

  test "a reconcile-scoped token records an applied report" do
    post_reconciliation({ event_id: @event.id, status: "applied" })

    assert_response :ok
    assert_request_schema_confirm
    assert_response_schema_confirm(200)
    assert_equal "applied", @access.reload.provisioning_status
    assert_equal true, JSON.parse(response.body)["access_present"]
  end

  test "a full token may also reconcile" do
    post_reconciliation({ event_id: @event.id, status: "failed" }, token: @full_raw)
    assert_response :ok
    assert_equal "failed", @access.reload.provisioning_status
  end

  test "a reconcile-scoped token is forbidden on the management API" do
    get "/api/v1/users", headers: { "Authorization" => "Bearer #{@reconcile_raw}" }
    assert_response :forbidden
    assert_equal "scope_insufficient", JSON.parse(response.body).dig("error", "code")
  end

  test "an unknown event id is a 422" do
    post_reconciliation({ event_id: SecureRandom.uuid, status: "applied" })
    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    assert_equal "unknown_event", JSON.parse(response.body).dig("error", "code")
  end

  test "an invalid status is a 422" do
    post_reconciliation({ event_id: @event.id, status: "nope" })
    assert_response :unprocessable_content
    assert_equal "invalid_status", JSON.parse(response.body).dig("error", "code")
  end

  test "an event from a different application is a 422" do
    other = Application.create!(name: "AWS", slug: "aws")
    post_reconciliation({ event_id: @event.id, status: "applied" }, app_id: other.id)
    assert_response :unprocessable_content
    assert_equal "event_application_mismatch", JSON.parse(response.body).dig("error", "code")
  end

  test "an unknown application is a 404" do
    post_reconciliation({ event_id: @event.id, status: "applied" }, app_id: SecureRandom.uuid)
    assert_response :not_found
  end

  test "no token is unauthorized" do
    post "/api/v1/applications/#{@application.id}/reconciliations",
         params: { event_id: @event.id, status: "applied" }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end
end
