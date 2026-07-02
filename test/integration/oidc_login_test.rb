require "test_helper"

# Exercises OmniauthSessionsController#callback through the real OmniAuth middleware
# stack using OmniAuth's test mode (mock_auth keyed by the strategy name). The
# callback's job is the STRICT identity lookup: hit + active → sign in; miss or
# inactive → the unregistered page; never auto-link.
class OidcLoginTest < ActionDispatch::IntegrationTest
  def setup
    @provider = AuthProvider.create!(
      name: "Keycloak", slug: "keycloak",
      oidc_issuer_url: "https://idp.example.com/realms/main",
      oidc_client_id: "governauthzer", oidc_scope: "openid email profile",
      claim_mappings: [], enabled: true
    )
    OmniAuth.config.test_mode = true
  end

  def teardown
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:openid_connect] = nil
  end

  def mock_oidc(uid:)
    OmniAuth.config.mock_auth[:openid_connect] =
      OmniAuth::AuthHash.new(provider: "openid_connect", uid: uid)
  end

  test "a STRICT miss renders the unregistered page (403) and shows the subject, without signing in" do
    mock_oidc(uid: "unknown-subject-xyz")

    assert_no_difference("AuditEvent.where(event_type: 'auth.login.succeeded').count") do
      get "/auth/#{@provider.slug}/callback"
    end
    assert_response :forbidden
    assert_includes response.body, "unknown-subject-xyz", "the IdP subject is shown for the operator to link"
    assert cookies[:session].blank?, "no session is established on a miss"
  end

  test "a registered, active identity signs in and emits an audit event" do
    user = User.create!(email: "ada@example.com", name: "Ada")
    @provider.omniauth_identities.create!(user: user, subject: "sub-abc")
    mock_oidc(uid: "sub-abc")

    assert_difference("AuditEvent.where(event_type: 'auth.login.succeeded').count", 1) do
      get "/auth/#{@provider.slug}/callback"
    end
    assert_redirected_to root_path
    assert cookies[:session].present?, "a session cookie is set"
  end

  test "a non-operator lands on the end-user dashboard, not the admin UI" do
    user = User.create!(email: "eve@example.com", name: "Eve Enduser")
    @provider.omniauth_identities.create!(user: user, subject: "sub-eve")
    mock_oidc(uid: "sub-eve")

    get "/auth/#{@provider.slug}/callback"
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success, "the landing page must not be the admin 403"
  end

  test "an operator also lands on the dashboard and can reach the admin UI from there" do
    user = User.create!(email: "opal@example.com", name: "Opal Operator")
    app = Application.create!(name: "governauthzer", slug: Application::SELF_SLUG)
    role = app.roles.create!(name: "Operator", slug: "operator", protected: true)
    Access.create!(user: user, role: role, status: "approved", source: "manual")
    @provider.omniauth_identities.create!(user: user, subject: "sub-opal")
    mock_oidc(uid: "sub-opal")

    get "/auth/#{@provider.slug}/callback"
    assert_redirected_to root_path
    get admin_root_path
    assert_response :success, "the operator gate must accept the session"
  end

  test "an inactive user is refused even with a linked identity" do
    user = User.create!(email: "susp@example.com", name: "Susp", status: "suspended")
    @provider.omniauth_identities.create!(user: user, subject: "sub-susp")
    mock_oidc(uid: "sub-susp")

    assert_no_difference("AuditEvent.where(event_type: 'auth.login.succeeded').count") do
      get "/auth/#{@provider.slug}/callback"
    end
    assert_response :forbidden
    assert cookies[:session].blank?
  end

  test "the failure endpoint redirects to login with an alert" do
    get "/auth/failure", params: { message: "csrf_detected" }
    assert_redirected_to login_path
    assert_match(/sign-in failed/i, flash[:alert])
  end
end
