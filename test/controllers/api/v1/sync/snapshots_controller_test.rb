require "test_helper"

class Api::V1::Sync::SnapshotsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @source_raw = ApiToken.generate_raw_token
    @source_token = ApiToken.create!(name: "workday-agent", source: "workday", token_digest: ApiToken.digest(@source_raw))

    @mgmt_raw = ApiToken.generate_raw_token
    @mgmt_token = ApiToken.create!(name: "mgmt", token_digest: ApiToken.digest(@mgmt_raw))
  end

  # --- helpers ---------------------------------------------------------------

  def post_snapshot(body, token: @source_raw)
    post "/api/v1/sync/snapshots",
         params: body.to_json,
         headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
  end

  def alice_payload(overrides = {})
    { external_id: "EMP-1001", email: "alice@example.com", name: "Alice Active" }.merge(overrides)
  end

  def bob_payload(overrides = {})
    { external_id: "EMP-1002", email: "bob@example.com", name: "Bob Pending" }.merge(overrides)
  end

  # --- happy path ------------------------------------------------------------

  test "creates new users, updates changed ones, leaves unchanged alone" do
    body = {
      as_of: 1.hour.ago.utc.iso8601,
      expected_count: 3,
      users: [
        alice_payload(name: "Alice Renamed", department: "Engineering"),
        bob_payload,
        { external_id: "EMP-1003", email: "carol@example.com", name: "Carol New" }
      ]
    }

    assert_difference("User.count", 1) do
      assert_difference("SnapshotRun.count", 1) do
        post_snapshot(body)
      end
    end

    assert_response :ok
    assert_request_schema_confirm
    assert_response_schema_confirm(200)

    json = JSON.parse(response.body)
    assert_equal "workday", json["source"]
    assert_equal true, json["applied"]
    assert_equal 1, json.dig("diff", "users_created")
    assert_equal 1, json.dig("diff", "users_updated")
    assert_equal 1, json.dig("diff", "users_unchanged")
    assert_empty json["orphaned"]

    carol = ExternalIdentity.find_by(source: "workday", external_id: "EMP-1003").user
    assert_equal "carol@example.com", carol.email
  end

  test "emits sync.snapshot.applied plus per-user events" do
    body = {
      as_of: 1.hour.ago.utc.iso8601,
      expected_count: 2,
      users: [ alice_payload(department: "Ops"), bob_payload ]
    }

    assert_difference("AuditEvent.where(event_type: 'sync.snapshot.applied').count", 1) do
      assert_difference("AuditEvent.where(event_type: 'user.updated').count", 1) do
        post_snapshot(body)
      end
    end
    assert_response :ok
  end

  test "snapshot audit events use the api channel and carry hris_source" do
    post_snapshot({
      as_of: 1.hour.ago.utc.iso8601,
      expected_count: 3,
      users: [ alice_payload, bob_payload, { external_id: "EMP-1003", email: "carol@example.com", name: "Carol" } ]
    })
    assert_response :ok

    created = AuditEvent.where(event_type: "user.created").order(occurred_at: :desc).first
    assert_equal "api", created.metadata["source"], "metadata.source must be the channel, not the HRIS source"
    assert_equal "snapshot", created.metadata["via"]
    assert_equal "workday", created.metadata["hris_source"]

    applied = AuditEvent.find_by(event_type: "sync.snapshot.applied")
    assert_equal "api", applied.metadata["source"]
    assert_equal "workday", applied.metadata["hris_source"]
  end

  # --- auth / scope ----------------------------------------------------------

  test "rejects a token without source scope" do
    post_snapshot({ as_of: 1.hour.ago.utc.iso8601, expected_count: 0, users: [] }, token: @mgmt_raw)

    assert_response :forbidden
    assert_response_schema_confirm(403)
    assert_equal "source_scope_required", JSON.parse(response.body).dig("error", "code")
  end

  test "rejects a missing token" do
    post "/api/v1/sync/snapshots", params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  # --- dry run ---------------------------------------------------------------

  test "dry_run returns diff without writing" do
    body = {
      as_of: 1.hour.ago.utc.iso8601,
      expected_count: 3,
      dry_run: true,
      users: [ alice_payload(name: "Alice Renamed"), bob_payload, { external_id: "EMP-1003", email: "carol@example.com", name: "Carol" } ]
    }

    assert_no_difference([ "User.count", "SnapshotRun.count", "AuditEvent.count" ]) do
      post_snapshot(body)
    end

    assert_response :ok
    assert_response_schema_confirm(200)
    json = JSON.parse(response.body)
    assert_equal false, json["applied"]
    assert_nil json["snapshot_run_id"]
    assert_equal 1, json.dig("diff", "users_created")
  end

  # --- validation errors -----------------------------------------------------

  test "count_mismatch when expected_count drifts more than 5%" do
    post_snapshot({ as_of: 1.hour.ago.utc.iso8601, expected_count: 100, users: [ alice_payload, bob_payload ] })

    assert_response :bad_request
    assert_response_schema_confirm(400)
    assert_equal "count_mismatch", JSON.parse(response.body).dig("error", "code")
  end

  test "terminated status in payload is rejected" do
    post_snapshot({ as_of: 1.hour.ago.utc.iso8601, expected_count: 2, users: [ alice_payload(status: "terminated"), bob_payload ] })

    assert_response :bad_request
    assert_equal "terminated_in_snapshot", JSON.parse(response.body).dig("error", "code")
  end

  test "as_of in the future is rejected" do
    post_snapshot({ as_of: 1.hour.from_now.utc.iso8601, expected_count: 2, users: [ alice_payload, bob_payload ] })

    assert_response :bad_request
    assert_response_schema_confirm(400)
    assert_equal "as_of_in_future", JSON.parse(response.body).dig("error", "code")
  end

  test "per-user validation collects all errors" do
    post_snapshot({
      as_of: 1.hour.ago.utc.iso8601,
      expected_count: 2,
      users: [ alice_payload(email: "not-an-email"), bob_payload(name: "") ]
    })

    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    json = JSON.parse(response.body)
    assert_equal "validation_failed", json.dig("error", "code")
    assert_equal 2, json.dig("error", "details", "errors").size
  end

  # --- freshness -------------------------------------------------------------

  test "stale, duplicate, and conflicting snapshots are rejected" do
    t0 = 2.hours.ago.change(usec: 0)
    baseline = { as_of: t0.utc.iso8601, expected_count: 2, users: [ alice_payload, bob_payload ] }
    post_snapshot(baseline)
    assert_response :ok

    # stale: older as_of
    post_snapshot({ as_of: (t0 - 1.hour).utc.iso8601, expected_count: 2, users: [ alice_payload, bob_payload ] })
    assert_response :conflict
    assert_equal "stale_snapshot", JSON.parse(response.body).dig("error", "code")

    # duplicate: same as_of, identical payload
    post_snapshot(baseline)
    assert_response :conflict
    assert_equal "duplicate_snapshot", JSON.parse(response.body).dig("error", "code")

    # conflicting: same as_of, different payload
    post_snapshot({ as_of: t0.utc.iso8601, expected_count: 2, users: [ alice_payload(name: "Alice X"), bob_payload ] })
    assert_response :conflict
    assert_equal "conflicting_snapshot", JSON.parse(response.body).dig("error", "code")
  end

  # --- circuit breaker -------------------------------------------------------

  test "mass termination is blocked then allowed with override" do
    # Dropping bob orphans 1 of 2 workday users = 50% > 10% threshold.
    drop_bob = { as_of: 1.hour.ago.utc.iso8601, expected_count: 1, users: [ alice_payload ] }

    post_snapshot(drop_bob)
    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    assert_equal "mass_termination_blocked", JSON.parse(response.body).dig("error", "code")
    assert_equal "pending_start", User.find_by(email: "bob@example.com").status, "bob must be untouched when blocked"

    post_snapshot(drop_bob.merge(override_circuit_breaker: true))
    assert_response :ok
    assert_equal "orphaned", User.find_by(email: "bob@example.com").status
  end

  # --- orphan cascade --------------------------------------------------------

  test "dropping a user's last identity orphans them and revokes access" do
    bob = users(:bob)
    app = Application.create!(name: "Slack", slug: "slack")
    role = Role.create!(application: app, name: "Slack User", slug: "slack-user")
    Access.create!(user: bob, role: role, status: "approved", source: "manual")
    prior_version = bob.session_version

    assert_difference("AuditEvent.where(event_type: 'access.revoked').count", 1) do
      assert_difference("AuditEvent.where(event_type: 'user.orphaned').count", 1) do
        post_snapshot({ as_of: 1.hour.ago.utc.iso8601, expected_count: 1, users: [ alice_payload ], override_circuit_breaker: true })
      end
    end

    assert_response :ok
    bob.reload
    assert_equal "orphaned", bob.status
    assert_not_nil bob.orphaned_at
    assert_equal prior_version + 1, bob.session_version
    assert_equal 0, bob.accesses.count
    assert_nil ExternalIdentity.find_by(source: "workday", external_id: "EMP-1002")
  end

  test "user with another source survives a single-source drop" do
    bob = users(:bob)
    ExternalIdentity.create!(user: bob, source: "bamboo", external_id: "B-2")

    post_snapshot({ as_of: 1.hour.ago.utc.iso8601, expected_count: 1, users: [ alice_payload ] })

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 1, json.dig("diff", "identities_dropped")
    assert_equal 0, json.dig("diff", "users_orphaned")

    bob.reload
    assert_not bob.orphaned?
    assert_equal "pending_start", bob.status
    assert_nil ExternalIdentity.find_by(source: "workday", external_id: "EMP-1002")
    assert ExternalIdentity.exists?(source: "bamboo", external_id: "B-2")
  end

  # --- manager resolution ----------------------------------------------------

  test "resolves manager within the batch, including forward references" do
    body = {
      as_of: 1.hour.ago.utc.iso8601,
      expected_count: 4,
      users: [
        alice_payload, bob_payload,
        { external_id: "EMP-1003", email: "carol@example.com", name: "Carol", manager_external_id: "EMP-1004" },
        { external_id: "EMP-1004", email: "dave@example.com", name: "Dave" }
      ]
    }

    post_snapshot(body)
    assert_response :ok

    carol = ExternalIdentity.find_by(source: "workday", external_id: "EMP-1003").user
    dave  = ExternalIdentity.find_by(source: "workday", external_id: "EMP-1004").user
    assert_equal dave.id, carol.manager_id
  end

  test "dangling manager produces a warning, not a failure" do
    body = {
      as_of: 1.hour.ago.utc.iso8601,
      expected_count: 3,
      users: [
        alice_payload, bob_payload,
        { external_id: "EMP-1003", email: "carol@example.com", name: "Carol", manager_external_id: "EMP-9999" }
      ]
    }

    post_snapshot(body)
    assert_response :ok
    warnings = JSON.parse(response.body)["warnings"]
    assert_equal "dangling_manager", warnings.first["code"]
  end
end
