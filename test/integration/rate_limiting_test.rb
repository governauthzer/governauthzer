require "test_helper"

class RateLimitingTest < ActionDispatch::IntegrationTest
  # Rack::Attack is disabled in test by default (so the rest of the suite isn't
  # throttled). These tests flip it on with a real per-process cache store, since
  # the default test cache is :null_store and would never accumulate counts.
  def setup
    @original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    Rack::Attack.enabled = true
  end

  def teardown
    Rack::Attack.enabled = false
    Rack::Attack.cache.store = @original_store
  end

  test "trips the emergency-login per-IP throttle and returns the rate_limited envelope" do
    # Limit is 5 per 20s; the 6th request from the same IP is throttled.
    5.times do
      get "/emergency-login/does-not-exist"
      assert_not_equal 429, response.status
    end

    get "/emergency-login/does-not-exist"

    assert_response :too_many_requests
    assert_equal "rate_limited", JSON.parse(response.body).dig("error", "code")
    assert response.headers["Retry-After"].to_i.positive?
    assert JSON.parse(response.body).dig("error", "details", "retry_after").positive?
  end

  test "lets requests under the limit through" do
    3.times do
      get "/emergency-login/does-not-exist"
      assert_not_equal 429, response.status
    end
  end

  test "throttles per API token by digest, not raw secret" do
    raw = ApiToken.generate_raw_token
    ApiToken.create!(name: "consumer", token_digest: ApiToken.digest(raw))
    headers = { "Authorization" => "Bearer #{raw}" }

    # Exercising the token-keyed throttle: well under 3000/min, so all pass and the
    # cache key never contains the raw token.
    2.times { get "/api/v1/whoami", headers: headers }
    assert_response :ok

    assert_nil Rack::Attack.cache.store.read("rack::attack:#{Time.now.to_i / 60}:api/token:#{raw}")
  end
end
