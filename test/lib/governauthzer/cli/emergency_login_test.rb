require "test_helper"
require "governauthzer/cli/emergency_login"

class Governauthzer::CLI::EmergencyLoginTest < ActiveSupport::TestCase
  test "prints a URL with the token in its fragment, never in the path" do
    out, = capture_io do
      Governauthzer::CLI::EmergencyLogin.new(user_email: users(:alice).email, reason: "test").run
    end

    url = out[%r{\S+/emergency-login\S*}]
    path, token = url.split("#", 2)
    assert path.end_with?("/emergency-login"), "the path carries no token: #{url}"
    assert EmergencyToken.find_by_raw_token(token)&.redeemable?, "the fragment is the live token"
    assert_includes out, "\n  #{token}\n", "the bare token is printed for pasting"
  end
end
