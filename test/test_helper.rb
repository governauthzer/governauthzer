ENV["RAILS_ENV"] ||= "test"

# Opt-in coverage: `COVERAGE=1 bin/rails test`. Kept out of the default run so the
# normal suite isn't slowed and CI behaviour is unchanged unless explicitly asked.
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch

    # Dev-only sign-in shortcut: its routes exist only in the development
    # environment, so it is unreachable (and intentionally untested) under test.
    add_filter "app/controllers/dev"

    # The "rails" profile groups Controllers/Models/Mailers/Jobs/Helpers/Libraries;
    # add the app layers it doesn't know about.
    add_group "Services",    "app/services"
    add_group "Policies",    "app/policies"
    add_group "Serializers", "app/serializers"
  end
end

require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Coverage must be tracked per forked worker, then merged in the parent.
    if ENV["COVERAGE"]
      parallelize_setup do |worker|
        SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}"
      end

      parallelize_teardown do |_worker|
        SimpleCov.result
      end
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
  end
end

class ActionDispatch::IntegrationTest
  include Committee::Rails::Test::Methods

  def committee_options
    @committee_options ||= {
      schema_path: Rails.root.join("openapi/v1.yaml").to_s,
      prefix: "/api/v1",
      parse_response_by_content_type: true,
      ignore_response_fields_not_in_spec: true,
      strict_reference_validation: true
    }
  end
end
