require "test_helper"

class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @raw_token = ApiToken.generate_raw_token
    @token = ApiToken.create!(name: "test-consumer", token_digest: ApiToken.digest(@raw_token))
    @headers = { "Authorization" => "Bearer #{@raw_token}", "Content-Type" => "application/json" }
  end

  # ----- index ---------------------------------------------------------------

  test "index lists users with default sort" do
    get "/api/v1/users", headers: @headers
    assert_response :ok
    assert_response_schema_confirm(200)

    body = JSON.parse(response.body)
    assert_kind_of Array, body
    assert body.length >= 2
    assert_equal "2", response.headers["X-Total-Count"]
  end

  test "index applies status filter" do
    get "/api/v1/users", params: { status: "active" }, headers: @headers
    assert_response :ok
    body = JSON.parse(response.body)
    assert(body.all? { |u| u["status"] == "active" })
  end

  test "index returns 400 for invalid sort field" do
    get "/api/v1/users", params: { sort: "bogus" }, headers: @headers
    assert_response :bad_request
    assert_response_schema_confirm(400)
    body = JSON.parse(response.body)
    assert_equal "invalid_sort", body.dig("error", "code")
    assert_equal "bogus", body.dig("error", "details", "field")
  end

  test "index paginates with per_page" do
    get "/api/v1/users", params: { per_page: 1 }, headers: @headers
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 1, body.length
    assert response.headers["Link"].include?("rel=\"next\"")
  end

  # ----- show ----------------------------------------------------------------

  test "show returns full user with embedded identities" do
    alice = users(:alice)
    get "/api/v1/users/#{alice.id}", headers: @headers
    assert_response :ok
    assert_response_schema_confirm(200)

    body = JSON.parse(response.body)
    assert_equal alice.id, body["id"]
    assert_equal "alice@example.com", body["email"]
    assert_equal 1, body["external_identities"].length
    assert_equal "workday", body["external_identities"].first["source"]
    assert_equal [], body["omniauth_identities"]
    assert_equal [], body["roles"]
  end

  test "show returns 404 for unknown user" do
    get "/api/v1/users/00000000-0000-0000-0000-000000000000", headers: @headers
    assert_response :not_found
    assert_response_schema_confirm(404)
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code")
  end

  # ----- create --------------------------------------------------------------

  test "create with minimal attrs returns 201 and emits user.created" do
    payload = { user: { email: "carol@example.com", name: "Carol", start_date: Date.current.to_s } }

    assert_difference("User.count", 1) do
      assert_difference("AuditEvent.where(event_type: 'user.created').count", 1) do
        post "/api/v1/users", params: payload.to_json, headers: @headers
      end
    end

    assert_response :created
    assert_response_schema_confirm(201)

    body = JSON.parse(response.body)
    assert_equal "carol@example.com", body["email"]
    assert_equal "active", body["status"]
  end

  test "create with future start_date defaults to pending_start" do
    payload = { user: { email: "dave@example.com", name: "Dave", start_date: (Date.current + 30.days).to_s } }
    post "/api/v1/users", params: payload.to_json, headers: @headers

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "pending_start", body["status"]
  end

  test "create with inline external_identities" do
    payload = {
      user: {
        email: "eve@example.com",
        name: "Eve",
        external_identities: [
          { source: "Workday", external_id: "EMP-2001" }
        ]
      }
    }

    assert_difference("ExternalIdentity.count", 1) do
      post "/api/v1/users", params: payload.to_json, headers: @headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal 1, body["external_identities"].length
    assert_equal "workday", body["external_identities"].first["source"]
    assert_equal "EMP-2001", body["external_identities"].first["external_id"]
  end

  test "create with inline omniauth_identities" do
    provider = AuthProvider.create!(
      name: "Test OIDC", slug: "test-oidc",
      oidc_issuer_url: "https://idp.example.com",
      oidc_client_id: "client", oidc_client_secret: "secret"
    )

    payload = {
      user: {
        email: "frank@example.com",
        name: "Frank",
        omniauth_identities: [
          { auth_provider_slug: provider.slug, subject: "00u-frank" }
        ]
      }
    }

    assert_difference("OmniauthIdentity.count", 1) do
      post "/api/v1/users", params: payload.to_json, headers: @headers
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal 1, body["omniauth_identities"].length
    assert_equal provider.slug, body["omniauth_identities"].first["auth_provider_slug"]
    assert_equal "00u-frank", body["omniauth_identities"].first["subject"]
  end

  test "create returns 422 for unknown auth_provider_slug" do
    payload = {
      user: {
        email: "grace@example.com",
        name: "Grace",
        omniauth_identities: [
          { auth_provider_slug: "does-not-exist", subject: "00u-grace" }
        ]
      }
    }

    assert_no_difference("User.count") do
      post "/api/v1/users", params: payload.to_json, headers: @headers
    end

    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    body = JSON.parse(response.body)
    assert_equal "unknown_auth_provider_slug", body.dig("error", "code")
    assert_equal "does-not-exist", body.dig("error", "details", "slug")
  end

  test "create returns 409 for external_id collision" do
    alice = users(:alice)
    payload = {
      user: {
        email: "henry@example.com",
        name: "Henry",
        external_identities: [
          { source: "workday", external_id: "EMP-1001" }
        ]
      }
    }

    assert_no_difference("User.count") do
      post "/api/v1/users", params: payload.to_json, headers: @headers
    end

    assert_response :conflict
    assert_response_schema_confirm(409)
    body = JSON.parse(response.body)
    assert_equal "external_id_collision", body.dig("error", "code")
    assert_equal alice.id, body.dig("error", "details", "existing_user_id")
  end

  test "create returns 422 for missing email" do
    payload = { user: { name: "Nameless" } }
    post "/api/v1/users", params: payload.to_json, headers: @headers
    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body.dig("error", "code")
  end

  # ----- update --------------------------------------------------------------

  test "update modifies attributes and emits user.updated" do
    alice = users(:alice)
    payload = { user: { department: "Engineering", title: "Staff" } }

    assert_difference("AuditEvent.where(event_type: 'user.updated').count", 1) do
      patch "/api/v1/users/#{alice.id}", params: payload.to_json, headers: @headers
    end

    assert_response :ok
    assert_response_schema_confirm(200)
    body = JSON.parse(response.body)
    assert_equal "Engineering", body["department"]
    assert_equal "Staff", body["title"]
  end

  test "update allows legal status transition active to suspended" do
    alice = users(:alice)
    payload = { user: { status: "suspended" } }
    patch "/api/v1/users/#{alice.id}", params: payload.to_json, headers: @headers

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "suspended", body["status"]
  end

  test "suspending bumps session_version; reinstating does not bump again" do
    alice = users(:alice)
    prior = alice.session_version

    patch "/api/v1/users/#{alice.id}", params: { user: { status: "suspended" } }.to_json, headers: @headers
    assert_response :ok
    assert_equal prior + 1, alice.reload.session_version

    bumped = alice.session_version
    patch "/api/v1/users/#{alice.id}", params: { user: { status: "active" } }.to_json, headers: @headers
    assert_response :ok
    assert_equal bumped, alice.reload.session_version, "reinstatement should not bump session_version"
  end

  test "update rejects illegal status transition active to pending_start" do
    alice = users(:alice)
    payload = { user: { status: "pending_start" } }
    patch "/api/v1/users/#{alice.id}", params: payload.to_json, headers: @headers

    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    body = JSON.parse(response.body)
    assert_equal "validation_failed", body.dig("error", "code")
    assert body.dig("error", "details", "errors", "status").present?
  end

  test "update to terminated runs the cascade: revokes approved access and emits user.terminated" do
    alice = users(:alice)
    app = Application.create!(name: "Slack", slug: "slack")
    role = Role.create!(application: app, name: "Slack User", slug: "slack-user")
    Access.create!(user: alice, role: role, status: "approved", source: "manual")
    prior_version = alice.session_version

    assert_difference("AuditEvent.where(event_type: 'access.revoked').count", 1) do
      assert_difference("AuditEvent.where(event_type: 'user.terminated').count", 1) do
        patch "/api/v1/users/#{alice.id}", params: { user: { status: "terminated" } }.to_json, headers: @headers
      end
    end

    assert_response :ok
    assert_response_schema_confirm(200)
    body = JSON.parse(response.body)
    assert_equal "terminated", body["status"]
    assert_empty body["roles"]

    alice.reload
    assert_equal "terminated", alice.status
    assert_equal 0, alice.accesses.count
    assert_equal prior_version + 1, alice.session_version
  end

  test "update to terminated destroys a pending access without emitting access.revoked" do
    alice = users(:alice)
    app = Application.create!(name: "Slack", slug: "slack")
    role = Role.create!(application: app, name: "Slack User", slug: "slack-user")
    Access.create!(user: alice, role: role, status: "pending", source: "self_request")

    assert_no_difference("AuditEvent.where(event_type: 'access.revoked').count") do
      assert_difference("AuditEvent.where(event_type: 'user.terminated').count", 1) do
        patch "/api/v1/users/#{alice.id}", params: { user: { status: "terminated" } }.to_json, headers: @headers
      end
    end

    assert_response :ok
    assert_equal 0, alice.reload.accesses.count
  end

  test "update returns 422 reactivation_required on terminated user" do
    alice = users(:alice)
    alice.update_column(:status, "terminated")

    payload = { user: { department: "anything" } }
    patch "/api/v1/users/#{alice.id}", params: payload.to_json, headers: @headers

    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    body = JSON.parse(response.body)
    assert_equal "reactivation_required", body.dig("error", "code")
    assert_equal alice.id, body.dig("error", "details", "user_id")
  end

  test "update returns 404 for unknown user" do
    payload = { user: { department: "x" } }
    patch "/api/v1/users/00000000-0000-0000-0000-000000000000", params: payload.to_json, headers: @headers
    assert_response :not_found
    assert_response_schema_confirm(404)
  end

  # ----- manager_external_id -------------------------------------------------

  test "update resolves manager_external_id to manager_id" do
    alice = users(:alice)  # has external_identity (workday, EMP-1001)
    bob = users(:bob)      # has external_identity (workday, EMP-1002)

    payload = { user: { manager_external_id: { source: "workday", external_id: "EMP-1001" } } }
    patch "/api/v1/users/#{bob.id}", params: payload.to_json, headers: @headers

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal alice.id, body["manager_id"]
  end

  test "update normalizes source on manager_external_id lookup" do
    bob = users(:bob)
    payload = { user: { manager_external_id: { source: "Workday", external_id: "EMP-1001" } } }
    patch "/api/v1/users/#{bob.id}", params: payload.to_json, headers: @headers

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal users(:alice).id, body["manager_id"]
  end

  test "update returns 422 conflicting_manager_ref when both manager_id and manager_external_id set" do
    alice = users(:alice)
    bob = users(:bob)
    payload = {
      user: {
        manager_id: alice.id,
        manager_external_id: { source: "workday", external_id: "EMP-1001" }
      }
    }
    patch "/api/v1/users/#{bob.id}", params: payload.to_json, headers: @headers

    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    body = JSON.parse(response.body)
    assert_equal "conflicting_manager_ref", body.dig("error", "code")
  end

  test "update returns 422 manager_not_found when manager_external_id does not resolve" do
    bob = users(:bob)
    payload = { user: { manager_external_id: { source: "workday", external_id: "EMP-NOPE" } } }
    patch "/api/v1/users/#{bob.id}", params: payload.to_json, headers: @headers

    assert_response :unprocessable_content
    assert_response_schema_confirm(422)
    body = JSON.parse(response.body)
    assert_equal "manager_not_found", body.dig("error", "code")
    assert_equal "workday", body.dig("error", "details", "source")
    assert_equal "EMP-NOPE", body.dig("error", "details", "external_id")
  end

  test "update clears manager when manager_external_id is null" do
    alice = users(:alice)
    bob = users(:bob)
    bob.update_column(:manager_id, alice.id)

    payload = { user: { manager_external_id: nil } }
    patch "/api/v1/users/#{bob.id}", params: payload.to_json, headers: @headers

    assert_response :ok
    body = JSON.parse(response.body)
    assert_nil body["manager_id"]
  end

  test "create accepts manager_external_id" do
    alice = users(:alice)
    payload = {
      user: {
        email: "new@example.com",
        name: "New",
        manager_external_id: { source: "workday", external_id: "EMP-1001" }
      }
    }
    post "/api/v1/users", params: payload.to_json, headers: @headers

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal alice.id, body["manager_id"]
  end

  # ----- destroy -------------------------------------------------------------

  test "destroy returns 405 with structured error" do
    alice = users(:alice)
    delete "/api/v1/users/#{alice.id}", headers: @headers

    assert_response :method_not_allowed
    assert_response_schema_confirm(405)
    body = JSON.parse(response.body)
    assert_equal "method_not_allowed", body.dig("error", "code")
  end
end
