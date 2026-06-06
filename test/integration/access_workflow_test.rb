require "test_helper"

class AccessWorkflowTest < ActionDispatch::IntegrationTest
  def setup
    @application = Application.create!(name: "Slack", slug: "slack")
    @manager = User.create!(email: "mgr@example.com", name: "Manager")
    @requester = User.create!(email: "req@example.com", name: "Requester", manager: @manager)
    @workflow = ApprovalWorkflow.create!(name: "Manager", slug: "mgr-flow")
    @workflow.approval_steps.create!(position: 0, strategy: "manager_of_requester", fallback_user: @manager)
    @role = Role.create!(application: @application, name: "Slack User", slug: "slack-user", approval_workflow: @workflow)
  end

  test "dashboard requires login" do
    get "/"
    assert_redirected_to "/login"
  end

  test "catalog lists requestable roles" do
    sign_in_as @requester
    get "/catalog"
    assert_response :ok
    assert_includes response.body, @role.name
  end

  test "end-to-end: request, appears in approver inbox, approve grants access" do
    sign_in_as @requester
    assert_enqueued_emails 1 do
      post "/access_requests", params: { role_id: @role.id, justification: "need it" }
    end
    assert_redirected_to "/"
    access = Access.find_by!(user: @requester, role: @role)
    assert_equal "pending", access.status

    sign_in_as @manager
    get "/"
    assert_response :ok
    assert_includes response.body, @requester.name

    # one email to the requester on grant
    assert_enqueued_emails 1 do
      post "/approvals/#{access.id}/approve", params: { comment: "ok" }
    end
    assert_equal "approved", access.reload.status
  end

  test "non-approver cannot approve" do
    sign_in_as @requester
    post "/access_requests", params: { role_id: @role.id }
    access = Access.find_by!(user: @requester, role: @role)

    # requester (not the approver) tries to approve their own request
    post "/approvals/#{access.id}/approve"
    assert_redirected_to "/"
    assert_equal "pending", access.reload.status
  end

  test "requester can withdraw their own pending request" do
    sign_in_as @requester
    post "/access_requests", params: { role_id: @role.id }
    access = Access.find_by!(user: @requester, role: @role)

    assert_difference("AuditEvent.where(event_type: 'access.withdrawn').count", 1) do
      delete "/access_requests/#{access.id}"
    end
    assert_not Access.exists?(access.id)
  end

  test "approver can deny, destroying the request" do
    sign_in_as @requester
    post "/access_requests", params: { role_id: @role.id }
    access = Access.find_by!(user: @requester, role: @role)

    sign_in_as @manager
    assert_enqueued_emails 1 do
      assert_difference("AuditEvent.where(event_type: 'access.denied').count", 1) do
        post "/approvals/#{access.id}/deny", params: { comment: "no" }
      end
    end
    assert_not Access.exists?(access.id)
  end

  private

  def sign_in_as(user)
    raw = SecureRandom.urlsafe_base64(32)
    EmergencyToken.create!(user: user, token_digest: EmergencyToken.digest(raw),
                           reason: "test sign-in", expires_at: 5.minutes.from_now)
    get "/emergency-login/#{raw}"
  end
end
