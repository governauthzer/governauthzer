require "test_helper"

# Emergency-login redemption (the break-glass / bootstrap path), logout, and the
# login page. The happy redemption path is exercised by every admin test's
# sign_in_as helper; this pins the failure branches and the session lifecycle.
class AuthSessionsTest < ActionDispatch::IntegrationTest
  def issue_token(user, expires_at: 5.minutes.from_now)
    raw = SecureRandom.urlsafe_base64(32)
    EmergencyToken.create!(user: user, token_digest: EmergencyToken.digest(raw),
                           reason: "test", expires_at: expires_at)
    raw
  end

  test "redeeming a valid token signs the user in and audits" do
    user = User.create!(email: "u@example.com", name: "U")
    raw = issue_token(user)

    assert_difference("AuditEvent.where(event_type: 'auth.emergency_login.succeeded').count", 1) do
      get "/emergency-login/#{raw}"
    end
    assert_response :ok
    assert cookies[:session].present?
  end

  test "a token can only be redeemed once" do
    user = User.create!(email: "once@example.com", name: "Once")
    raw = issue_token(user)

    get "/emergency-login/#{raw}"
    assert_response :ok

    get "/emergency-login/#{raw}"
    assert_response :not_found
  end

  test "an expired token is rejected without auditing" do
    user = User.create!(email: "exp@example.com", name: "Exp")
    raw = issue_token(user, expires_at: 1.minute.ago)

    assert_no_difference("AuditEvent.count") do
      get "/emergency-login/#{raw}"
    end
    assert_response :not_found
  end

  test "a token for an inactive user is rejected" do
    user = User.create!(email: "susp@example.com", name: "Susp", status: "suspended")
    raw = issue_token(user)

    get "/emergency-login/#{raw}"
    assert_response :not_found
  end

  test "an unknown token is rejected" do
    get "/emergency-login/gva-not-a-real-token"
    assert_response :not_found
  end

  test "logout clears the session and redirects to login" do
    user = User.create!(email: "out@example.com", name: "Out")
    get "/emergency-login/#{issue_token(user)}"
    assert cookies[:session].present?

    delete "/logout"
    assert_redirected_to login_path
    assert cookies[:session].blank?
  end

  test "the login page lists only enabled providers" do
    AuthProvider.create!(name: "VisibleIdP", slug: "visible", oidc_issuer_url: "https://i",
                         oidc_client_id: "c", oidc_scope: "openid", claim_mappings: [], enabled: true)
    AuthProvider.create!(name: "HiddenIdP", slug: "hidden", oidc_issuer_url: "https://i",
                         oidc_client_id: "c", oidc_scope: "openid", claim_mappings: [], enabled: false)

    get "/login"
    assert_response :ok
    assert_includes response.body, "VisibleIdP"
    assert_not_includes response.body, "HiddenIdP"
  end
end
