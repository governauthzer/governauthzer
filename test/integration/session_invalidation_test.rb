require "test_helper"

# Sessions are signed-cookie bearer tokens valid for 24h. Carrying session_version
# in the cookie and checking it on every request makes them revocable: bumping a
# user's session_version (suspend/terminate/orphan today, an explicit operator
# force-logout later) invalidates every cookie issued before the bump.
class SessionInvalidationTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(email: "user@example.com", name: "User") # active
  end

  test "a valid session reaches an authenticated page" do
    sign_in_as @user
    get "/"
    assert_response :ok
  end

  test "bumping session_version on an active user invalidates the live session" do
    sign_in_as @user
    get "/"
    assert_response :ok

    # User stays active — this isolates session_version from the active? gate.
    @user.increment!(:session_version)

    get "/"
    assert_redirected_to "/login"
  end

  test "a fresh login after a bump issues a cookie with the current version" do
    sign_in_as @user
    @user.increment!(:session_version)

    sign_in_as @user # new emergency-login → cookie carries the bumped version
    get "/"
    assert_response :ok
  end

  private

  def sign_in_as(user)
    raw = SecureRandom.urlsafe_base64(32)
    EmergencyToken.create!(user: user, token_digest: EmergencyToken.digest(raw),
                           reason: "test sign-in", expires_at: 5.minutes.from_now)
    get "/emergency-login/#{raw}"
  end
end
