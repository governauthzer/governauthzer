require "test_helper"

# Guards the auth posture of the OpenAPI contract: a global BearerToken security
# default must exist, and no operation may opt out of it (`security: []` is the
# only way an endpoint could drift to unauthenticated in the spec).
class OpenapiSecurityTest < ActiveSupport::TestCase
  SPEC = YAML.safe_load_file(Rails.root.join("openapi/v1.yaml"))
  HTTP_METHODS = %w[get post put patch delete].freeze

  test "spec declares a global BearerToken security default" do
    assert_equal [ { "BearerToken" => [] } ], SPEC["security"]
  end

  test "no operation opts out of authentication" do
    SPEC["paths"].each do |path, operations|
      operations.slice(*HTTP_METHODS).each do |method, operation|
        security = operation["security"]
        next if security.nil? # inherits the global default

        assert_not_empty security, "#{method.upcase} #{path} overrides security with an empty array (unauthenticated)"
        assert(security.any? { |s| s.key?("BearerToken") },
               "#{method.upcase} #{path} declares security without BearerToken")
      end
    end
  end
end
