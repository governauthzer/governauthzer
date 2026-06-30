require "test_helper"

class Api::V1::DriftReportsControllerTest < ActionDispatch::IntegrationTest
  def setup
    Current.correlation_id = SecureRandom.uuid
    @reconcile_raw = ApiToken.generate_raw_token
    ApiToken.create!(name: "bridge", scope: "reconcile", token_digest: ApiToken.digest(@reconcile_raw))
    @full_raw = ApiToken.generate_raw_token
    ApiToken.create!(name: "mgmt", token_digest: ApiToken.digest(@full_raw))
  end

  def sample_body
    {
      observed_at: "2026-06-30T10:00:00Z",
      reports: [
        {
          application_slug: "slack",
          role_slug: "slack-admin",
          missing: [ { user_id: SecureRandom.uuid, email: "grace@example.com" } ],
          extra: [ { email: "mallory@example.com" } ]
        }
      ]
    }
  end

  def post_drift(body, token: @reconcile_raw)
    post "/api/v1/drift-reports",
         params: body.to_json,
         headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  end

  def drift_audits
    AuditEvent.where(event_type: "provisioning.drift_detected")
  end

  test "a reconcile-scoped token records a drift sweep" do
    assert_difference -> { drift_audits.count }, 1 do
      post_drift(sample_body)
    end
    assert_response :ok
    assert_request_schema_confirm
    assert_response_schema_confirm(200)

    body = JSON.parse(response.body)
    assert_equal true, body["recorded"]
    assert_equal 1, body["group_count"]
    assert_equal 1, body["missing_total"]
    assert_equal 1, body["extra_total"]
  end

  test "records the findings in audit metadata" do
    post_drift(sample_body)
    audit = drift_audits.last
    assert_equal "api", audit.metadata["source"]
    assert_equal "drift_reconciliation", audit.metadata["via"]
    assert_equal 1, audit.metadata["missing_total"]

    group = audit.metadata["groups"].first
    assert_equal "slack", group["application_slug"]
    assert_equal "grace@example.com", group["missing"].first["email"]
    assert_equal "mallory@example.com", group["extra"].first["email"]
  end

  test "writes exactly one audit event per sweep even across groups" do
    body = { reports: [
      { application_slug: "slack", role_slug: "admin", missing: [ { email: "a@x.com" } ], extra: [] },
      { application_slug: "github", role_slug: "eng", missing: [], extra: [ { email: "b@x.com" } ] }
    ] }
    assert_difference -> { drift_audits.count }, 1 do
      post_drift(body)
    end
    assert_equal 2, drift_audits.last.metadata["group_count"]
  end

  test "a full token may also report drift" do
    post_drift(sample_body, token: @full_raw)
    assert_response :ok
  end

  test "an empty reports array is a 422" do
    post_drift({ reports: [] })
    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    assert_equal "invalid_drift_report", JSON.parse(response.body).dig("error", "code")
  end

  test "no token is unauthorized" do
    post "/api/v1/drift-reports", params: sample_body.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end
end
