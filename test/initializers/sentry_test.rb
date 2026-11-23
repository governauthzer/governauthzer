require "test_helper"

# Sentry is not initialized under test (no SENTRY_DSN), so the setup is applied to a
# fresh configuration instead — initializing it here would patch Net::HTTP for every
# test in the process.
class SentrySetupTest < ActiveSupport::TestCase
  test "outbound HTTP is not instrumented, so webhook URLs never reach Sentry" do
    config = Sentry::Configuration.new
    Governauthzer::SENTRY_SETUP.call(config)

    assert_not_includes config.enabled_patches, :http, "the patch records URLs with their secret path"
    assert_not_includes config.breadcrumbs_logger, :http_logger
  end

  test "PII stays off unless explicitly enabled" do
    config = Sentry::Configuration.new
    Governauthzer::SENTRY_SETUP.call(config)
    assert_not config.send_default_pii
  end
end
