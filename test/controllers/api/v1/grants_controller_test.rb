require "test_helper"

class Api::V1::GrantsControllerTest < ActionDispatch::IntegrationTest
  def setup
    Current.correlation_id = SecureRandom.uuid

    @slack = Application.create!(name: "Slack", slug: "slack")
    @slack_admin = Role.create!(application: @slack, name: "Admin", slug: "slack-admin")

    @active = User.create!(email: "ada@example.com", name: "Ada", start_date: Date.new(2026, 1, 1))
    @suspended = User.create!(email: "grace@example.com", name: "Grace", start_date: Date.new(2026, 1, 1))
    @suspended.update!(status: "suspended")

    Access.create!(user: @active, role: @slack_admin, status: "approved", provisioning_status: "applied")
    Access.create!(user: @suspended, role: @slack_admin, status: "approved", provisioning_status: "applied")
    # A pending (not yet approved) request must NOT appear.
    pending_user = User.create!(email: "pat@example.com", name: "Pat", start_date: Date.new(2026, 1, 1))
    Access.create!(user: pending_user, role: @slack_admin, status: "pending", provisioning_status: "not_required")

    # The self/operator application's grants must be excluded.
    self_app = Application.create!(name: "Governauthzer", slug: Application::SELF_SLUG)
    operator_role = Role.create!(application: self_app, name: "Operator", slug: "operator")
    Access.create!(user: @active, role: operator_role, status: "approved", provisioning_status: "not_required")

    @reconcile_raw = ApiToken.generate_raw_token
    ApiToken.create!(name: "bridge", scope: "reconcile", token_digest: ApiToken.digest(@reconcile_raw))
    @full_raw = ApiToken.generate_raw_token
    ApiToken.create!(name: "mgmt", token_digest: ApiToken.digest(@full_raw))
  end

  def get_grants(token: @reconcile_raw, params: {})
    get "/api/v1/grants", params: params, headers: { "Authorization" => "Bearer #{token}" }
  end

  test "a reconcile-scoped token may read grants" do
    get_grants
    assert_response :ok
    assert_response_schema_confirm(200)
  end

  test "a full token may also read grants" do
    get_grants(token: @full_raw)
    assert_response :ok
  end

  test "returns approved grants for active and suspended users, excluding self-app and pending" do
    get_grants
    body = JSON.parse(response.body)

    emails = body.map { |g| g.dig("user", "email") }.sort
    assert_equal [ "ada@example.com", "grace@example.com" ], emails

    g = body.find { |x| x.dig("user", "email") == "ada@example.com" }
    assert_equal "slack", g.dig("application", "slug")
    assert_equal "slack-admin", g.dig("role", "slug")
    assert_equal @active.id, g.dig("user", "id")

    refute_includes body.map { |x| x.dig("role", "slug") }, "operator"
  end

  test "sets pagination headers" do
    get_grants
    assert_equal "2", response.headers["X-Total-Count"]
    assert_match(/rel="first"/, response.headers["Link"])
  end

  test "respects per_page paging" do
    get_grants(params: { per_page: 1, page: 1 })
    assert_equal "2", response.headers["X-Total-Count"]
    assert_equal 1, JSON.parse(response.body).size
    assert_match(/rel="next"/, response.headers["Link"])
  end

  test "no token is unauthorized" do
    get "/api/v1/grants"
    assert_response :unauthorized
  end
end
