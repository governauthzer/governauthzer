require "test_helper"

# Emergency-login redemption (the break-glass / bootstrap path), logout, and the
# login page. The happy redemption path is exercised by every integration test's
# sign_in_as helper; this pins the failure branches, the token's absence from paths
# and logs, and the session lifecycle.
class AuthSessionsTest < ActionDispatch::IntegrationTest
  def redeem(raw)
    post "/emergency-login", params: { token: raw }
  end

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
      redeem(raw)
    end
    assert_redirected_to root_path
    assert cookies[:session].present?
  end

  test "the sign-in URL carries the token in its fragment, and the page asks before redeeming" do
    user = User.create!(email: "frag@example.com", name: "Frag")
    raw = issue_token(user)

    # Browsers don't send the fragment; what reaches the server is the bare path.
    assert_no_difference("AuditEvent.count") { get "/emergency-login" }
    assert_response :ok
    assert_select "form[action='/emergency-login'][method='post'] input[name='token'][type='password']"
    assert cookies[:session].blank?
    assert EmergencyToken.find_by_raw_token(raw).redeemable?, "opening the page must not burn the token"
  end

  test "a whole pasted URL is accepted in place of the token" do
    user = User.create!(email: "paste@example.com", name: "Paste")
    post "/emergency-login", params: { token: " https://gov.example.com/emergency-login##{issue_token(user)} " }
    assert_redirected_to root_path
  end

  test "the old token-in-path URL no longer exists" do
    user = User.create!(email: "old@example.com", name: "Old")
    raw = issue_token(user)
    get "/emergency-login/#{raw}"
    assert_response :not_found
    assert EmergencyToken.find_by_raw_token(raw).redeemable?
  end

  test "the token never reaches the request log" do
    user = User.create!(email: "log@example.com", name: "Log")
    raw = issue_token(user)
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)
    ActionController::Base.logger = Rails.logger
    begin
      redeem(raw)
    ensure
      Rails.logger = original
      ActionController::Base.logger = original
    end
    assert_includes log.string, "Started POST \"/emergency-login\""
    assert_not_includes log.string, raw
  end

  test "a token can only be redeemed once" do
    user = User.create!(email: "once@example.com", name: "Once")
    raw = issue_token(user)

    redeem(raw)
    assert_redirected_to root_path

    redeem(raw)
    assert_response :not_found
  end

  test "an expired token is rejected without auditing" do
    user = User.create!(email: "exp@example.com", name: "Exp")
    raw = issue_token(user, expires_at: 1.minute.ago)

    assert_no_difference("AuditEvent.count") do
      redeem(raw)
    end
    assert_response :not_found
  end

  test "a token for an inactive user is rejected" do
    user = User.create!(email: "susp@example.com", name: "Susp", status: "suspended")
    raw = issue_token(user)

    redeem(raw)
    assert_response :not_found
  end

  test "an unknown token is rejected" do
    redeem("gva-not-a-real-token")
    assert_response :not_found
  end

  test "logout clears the session and redirects to login" do
    user = User.create!(email: "out@example.com", name: "Out")
    redeem(issue_token(user))
    assert cookies[:session].present?

    delete "/logout"
    assert_redirected_to login_path
    assert cookies[:session].blank?
  end

  test "a sign-in failure shows fixed text, never the error from the query string" do
    get "/auth/failure", params: { message: "Your account is locked. Call +1 555 0100 to unlock" }
    assert_redirected_to login_path
    assert_equal "Sign-in failed. Try again or contact your administrator.", flash[:alert]

    follow_redirect!
    assert_not_includes response.body, "555 0100"
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
