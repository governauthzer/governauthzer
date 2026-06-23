require "test_helper"

class AdminApiTokensTest < ActionDispatch::IntegrationTest
  def setup
    @self_app = Application.create!(name: "Governauthzer", slug: Application::SELF_SLUG)
    operator_role = @self_app.roles.create!(name: "Operator", slug: "operator", protected: true)
    @operator = User.create!(email: "tokenop@example.com", name: "Token Op")
    Access.create!(user: @operator, role: operator_role, status: "approved", source: "manual")
    sign_in_as @operator
  end

  test "index and new render" do
    ApiToken.create!(name: "Existing", token_digest: ApiToken.digest(ApiToken.generate_raw_token))
    get "/admin/api_tokens"
    assert_response :ok
    assert_includes response.body, "Existing"

    get "/admin/api_tokens/new"
    assert_response :ok
  end

  test "create mints a full-access token, shows the plaintext once, and audits" do
    assert_difference([ "ApiToken.count", "AuditEvent.where(event_type: 'api_token.created').count" ], 1) do
      post "/admin/api_tokens", params: { api_token: { name: "HRIS sync" } }
    end
    assert_redirected_to "/admin/api_tokens"

    raw = flash[:plain_token]
    assert raw.to_s.start_with?("gva_"), "the plaintext token is surfaced once via flash"
    token = ApiToken.find_by_raw_token(raw)
    assert_not_nil token, "the shown token resolves to the stored digest"
    assert_equal "HRIS sync", token.name
    assert_equal "full", token.scope, "defaults to full access"
    assert_nil token.source
  end

  test "create accepts a reconcile scope and a source-scoped token" do
    post "/admin/api_tokens", params: { api_token: { name: "Bridge", scope: "reconcile", source: "Workday" } }
    token = ApiToken.find_by(name: "Bridge")
    assert_equal "reconcile", token.scope
    assert token.reconcile_scoped?
    assert_equal "workday", token.source, "source normalized like ExternalIdentity#source"
    assert token.sync_scoped?
  end

  test "destroy revokes the token and audits" do
    token = ApiToken.create!(name: "Old", token_digest: ApiToken.digest(ApiToken.generate_raw_token))
    assert_difference("ApiToken.count", -1) do
      assert_difference("AuditEvent.where(event_type: 'api_token.deleted').count", 1) do
        delete "/admin/api_tokens/#{token.id}"
      end
    end
    assert_redirected_to "/admin/api_tokens"
  end

  test "a non-operator is forbidden" do
    plain = User.create!(email: "plain-token@example.com", name: "Plain")
    sign_in_as plain
    get "/admin/api_tokens"
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
