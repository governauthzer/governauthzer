require "test_helper"

class AdminUsersTest < ActionDispatch::IntegrationTest
  def setup
    self_app = Application.create!(name: "Governauthzer", slug: Application::SELF_SLUG)
    operator_role = self_app.roles.create!(name: "Operator", slug: "operator", protected: true)
    @operator = User.create!(email: "op@example.com", name: "Op")
    Access.create!(user: @operator, role: operator_role, status: "approved", source: "manual")
    @target = User.create!(email: "target@example.com", name: "Target User")
    @provider = AuthProvider.create!(
      name: "Okta", slug: "okta", enabled: true,
      oidc_issuer_url: "https://okta.example.com", oidc_client_id: "cid",
      oidc_client_secret: "secret", oidc_scope: "openid email", claim_mappings: []
    )
    sign_in_as @operator
  end

  test "index lists users and renders status filter" do
    get "/admin/users"
    assert_response :ok
    assert_includes response.body, @target.name
    get "/admin/users", params: { status: "active" }
    assert_response :ok
  end

  test "user detail renders" do
    get "/admin/users/#{@target.id}"
    assert_response :ok
    assert_includes response.body, @target.email
  end

  test "operator suspends a user" do
    prior = @target.session_version
    assert_difference("AuditEvent.where(event_type: 'user.updated').count", 1) do
      patch "/admin/users/#{@target.id}", params: { user: { status: "suspended" } }
    end
    assert_equal "suspended", @target.reload.status
    assert_equal prior + 1, @target.session_version
  end

  test "operator terminates a user, revoking access" do
    app = Application.create!(name: "Slack", slug: "slack")
    role = app.roles.create!(name: "Member", slug: "member")
    Access.create!(user: @target, role: role, status: "approved", source: "manual")

    assert_difference("AuditEvent.where(event_type: 'user.terminated').count", 1) do
      patch "/admin/users/#{@target.id}", params: { user: { status: "terminated" } }
    end
    assert_equal "terminated", @target.reload.status
    assert_equal 0, @target.accesses.count
  end

  test "operator links and unlinks an OIDC identity" do
    assert_difference([ "OmniauthIdentity.count", "AuditEvent.where(event_type: 'omniauth_identity.linked').count" ], 1) do
      post "/admin/users/#{@target.id}/omniauth_identities",
           params: { omniauth_identity: { auth_provider_id: @provider.id, subject: "sub-123" } }
    end
    identity = @target.omniauth_identities.first

    assert_difference("OmniauthIdentity.count", -1) do
      assert_difference("AuditEvent.where(event_type: 'omniauth_identity.unlinked').count", 1) do
        delete "/admin/omniauth_identities/#{identity.id}"
      end
    end
  end

  test "linking a subject already taken by the provider fails gracefully" do
    other = User.create!(email: "other@example.com", name: "Other")
    OmniauthIdentity.create!(user: other, auth_provider: @provider, subject: "dup")

    assert_no_difference("OmniauthIdentity.count") do
      post "/admin/users/#{@target.id}/omniauth_identities",
           params: { omniauth_identity: { auth_provider_id: @provider.id, subject: "dup" } }
    end
    assert_redirected_to "/admin/users/#{@target.id}"
  end

  test "a non-operator is forbidden" do
    plain = User.create!(email: "plain@example.com", name: "Plain")
    sign_in_as plain
    get "/admin/users"
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
