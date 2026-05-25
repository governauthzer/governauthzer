require "test_helper"

class Api::V1::UsersByExternalIdControllerTest < ActionDispatch::IntegrationTest
  def setup
    @raw_token = ApiToken.generate_raw_token
    @token = ApiToken.create!(name: "test-consumer", token_digest: ApiToken.digest(@raw_token))
    @headers = { "Authorization" => "Bearer #{@raw_token}", "Content-Type" => "application/json" }
  end

  test "updates user found by (source, external_id)" do
    alice = users(:alice)
    payload = { user: { department: "Engineering" } }

    patch "/api/v1/users/by-external-id/workday/EMP-1001",
          params: payload.to_json, headers: @headers

    assert_response :ok
    assert_response_schema_confirm(200)
    body = JSON.parse(response.body)
    assert_equal alice.id, body["id"]
    assert_equal "Engineering", body["department"]
  end

  test "normalizes source so Workday in URL matches workday in DB" do
    patch "/api/v1/users/by-external-id/Workday/EMP-1001",
          params: { user: { title: "Lead" } }.to_json, headers: @headers

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "Lead", body["title"]
  end

  test "returns 404 external_identity_not_found for unknown (source, external_id)" do
    patch "/api/v1/users/by-external-id/workday/EMP-NOPE",
          params: { user: { title: "x" } }.to_json, headers: @headers

    assert_response :not_found
    assert_response_schema_confirm(404)
    body = JSON.parse(response.body)
    assert_equal "external_identity_not_found", body.dig("error", "code")
    assert_equal "workday", body.dig("error", "details", "source")
    assert_equal "EMP-NOPE", body.dig("error", "details", "external_id")
  end

  test "returns 422 reactivation_required when found user is terminated" do
    alice = users(:alice)
    alice.update_column(:status, "terminated")

    patch "/api/v1/users/by-external-id/workday/EMP-1001",
          params: { user: { title: "x" } }.to_json, headers: @headers

    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    body = JSON.parse(response.body)
    assert_equal "reactivation_required", body.dig("error", "code")
  end

  test "emits user.updated audit event same as UUID-path PATCH" do
    alice = users(:alice)

    assert_difference("AuditEvent.where(event_type: 'user.updated').count", 1) do
      patch "/api/v1/users/by-external-id/workday/EMP-1001",
            params: { user: { department: "Ops" } }.to_json, headers: @headers
    end

    assert_response :ok
    event = AuditEvent.where(event_type: "user.updated").order(occurred_at: :desc).first
    assert_equal alice.id, event.targets.first["id"]
  end
end
