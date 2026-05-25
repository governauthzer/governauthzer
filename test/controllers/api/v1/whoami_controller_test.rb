require "test_helper"

class Api::V1::WhoamiControllerTest < ActionDispatch::IntegrationTest
  def setup
    @raw_token = ApiToken.generate_raw_token
    @token = ApiToken.create!(name: "test-consumer", token_digest: ApiToken.digest(@raw_token))
  end

  def auth_header(raw)
    { "Authorization" => "Bearer #{raw}" }
  end

  test "returns token info with valid bearer token" do
    get "/api/v1/whoami", headers: auth_header(@raw_token)

    assert_response :ok
    assert_request_schema_confirm
    assert_response_schema_confirm(200)

    body = JSON.parse(response.body)
    assert_equal @token.id, body["token_id"]
    assert_equal "test-consumer", body["token_name"]
  end

  test "returns structured error envelope when Authorization header missing" do
    get "/api/v1/whoami"

    assert_response :unauthorized
    assert_response_schema_confirm(401)

    body = JSON.parse(response.body)
    assert_equal "unauthorized", body.dig("error", "code")
    assert body.dig("error", "message").present?
  end

  test "returns structured error envelope when bearer token is unknown" do
    get "/api/v1/whoami", headers: auth_header("gva_definitelynotarealtokenvalue1234567890abcdef")

    assert_response :unauthorized
    assert_response_schema_confirm(401)

    body = JSON.parse(response.body)
    assert_equal "unauthorized", body.dig("error", "code")
  end

  test "returns structured error envelope when bearer token is malformed (no gva_ prefix)" do
    get "/api/v1/whoami", headers: auth_header("bogus-token-without-prefix")

    assert_response :unauthorized
    assert_response_schema_confirm(401)

    body = JSON.parse(response.body)
    assert_equal "unauthorized", body.dig("error", "code")
  end

  test "returns structured error envelope when bearer token is expired" do
    expired_raw = ApiToken.generate_raw_token
    ApiToken.create!(
      name: "expired-consumer",
      token_digest: ApiToken.digest(expired_raw),
      expires_at: 1.hour.ago
    )

    get "/api/v1/whoami", headers: auth_header(expired_raw)

    assert_response :unauthorized
    assert_response_schema_confirm(401)

    body = JSON.parse(response.body)
    assert_equal "unauthorized", body.dig("error", "code")
  end
end
