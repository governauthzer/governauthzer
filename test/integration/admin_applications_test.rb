require "test_helper"

class AdminApplicationsTest < ActionDispatch::IntegrationTest
  def setup
    @self_app = Application.create!(name: "Governauthzer", slug: Application::SELF_SLUG)
    operator_role = @self_app.roles.create!(name: "Operator", slug: "operator", protected: true)
    @operator = User.create!(email: "op@example.com", name: "Op")
    Access.create!(user: @operator, role: operator_role, status: "approved", source: "manual")
    @workflow = ApprovalWorkflow.create!(name: "Manager", slug: "mgr")
    sign_in_as @operator
  end

  test "operator creates an application" do
    assert_difference([ "Application.count", "AuditEvent.where(event_type: 'application.created').count" ], 1) do
      post "/admin/applications", params: { application: { name: "Slack", slug: "Slack" } }
    end
    assert_equal "slack", Application.find_by(name: "Slack").slug, "slug normalized"
  end

  test "operator adds a role with workflow to an application" do
    app = Application.create!(name: "Slack", slug: "slack")
    assert_difference([ "Role.count", "AuditEvent.where(event_type: 'role.created').count" ], 1) do
      post "/admin/applications/#{app.id}/roles",
           params: { role: { name: "Member", slug: "member", protected: "0", approval_workflow_id: @workflow.id } }
    end
    role = app.roles.find_by!(slug: "member")
    assert_equal @workflow, role.approval_workflow
    assert_not role.protected?
  end

  test "operator edits and deletes a role" do
    app = Application.create!(name: "Slack", slug: "slack")
    role = app.roles.create!(name: "Member", slug: "member")

    patch "/admin/roles/#{role.id}", params: { role: { name: "Member v2", slug: "member", protected: "1" } }
    assert_equal "Member v2", role.reload.name
    assert role.protected?

    assert_difference("Role.count", -1) do
      delete "/admin/roles/#{role.id}"
    end
  end

  test "renaming a role slug warns when it has active grants (provisioning contract key)" do
    app = Application.create!(name: "Slack", slug: "slack")
    role = app.roles.create!(name: "Member", slug: "member")
    grantee = User.create!(email: "grantee@example.com", name: "Grantee")
    Access.create!(user: grantee, role: role, status: "approved", source: "manual")

    patch "/admin/roles/#{role.id}", params: { role: { name: "Member", slug: "member-v2" } }
    assert_equal "member-v2", role.reload.slug
    assert_match(/provisioning key/i, flash[:alert])
  end

  test "renaming a role slug does not warn without active grants" do
    app = Application.create!(name: "Slack", slug: "slack")
    role = app.roles.create!(name: "Member", slug: "member")

    patch "/admin/roles/#{role.id}", params: { role: { name: "Member", slug: "member-v2" } }
    assert_equal "member-v2", role.reload.slug
    assert_nil flash[:alert]
  end

  test "the system application is read-only" do
    patch "/admin/applications/#{@self_app.id}", params: { application: { name: "Hacked" } }
    assert_redirected_to "/admin/applications"
    assert_equal "Governauthzer", @self_app.reload.name

    delete "/admin/applications/#{@self_app.id}"
    assert Application.exists?(@self_app.id)
  end

  test "roles on the system application cannot be created via the UI" do
    get "/admin/applications/#{@self_app.id}/roles/new"
    assert_redirected_to "/admin/applications"
  end

  test "an application with roles cannot be deleted" do
    app = Application.create!(name: "Slack", slug: "slack")
    app.roles.create!(name: "Member", slug: "member")
    assert_no_difference("Application.count") do
      delete "/admin/applications/#{app.id}"
    end
    assert_redirected_to "/admin/applications"
  end

  test "operator CRUD pages render" do
    app = Application.create!(name: "Slack", slug: "slack")
    role = app.roles.create!(name: "Member", slug: "member", approval_workflow: @workflow)

    get "/admin/applications"
    assert_response :ok
    assert_includes response.body, "Slack"
    get "/admin/applications/new"
    assert_response :ok
    get "/admin/applications/#{app.id}"
    assert_response :ok
    assert_includes response.body, "Member"
    get "/admin/applications/#{app.id}/edit"
    assert_response :ok
    get "/admin/applications/#{app.id}/roles/new"
    assert_response :ok
    get "/admin/roles/#{role.id}/edit"
    assert_response :ok
  end

  test "a non-operator is forbidden" do
    plain = User.create!(email: "plain@example.com", name: "Plain")
    sign_in_as plain
    get "/admin/applications"
    assert_response :forbidden
  end

  private

  def sign_in_as(user)
    raw = SecureRandom.urlsafe_base64(32)
    EmergencyToken.create!(user: user, token_digest: EmergencyToken.digest(raw),
                           reason: "test sign-in", expires_at: 5.minutes.from_now)
    get "/emergency-login/#{raw}"
  end
end
