require "test_helper"

class AccessWorkflowTest < ActionDispatch::IntegrationTest
  def setup
    @application = Application.create!(name: "Slack", slug: "slack")
    @manager = User.create!(email: "mgr@example.com", name: "Manager")
    @requester = User.create!(email: "req@example.com", name: "Requester", manager: @manager)
    @workflow = ApprovalWorkflow.create!(name: "Manager", slug: "mgr-flow")
    @workflow.approval_steps.create!(position: 0, strategy: "manager_of_requester", fallback_user: @manager)
    @role = Role.create!(application: @application, name: "Slack User", slug: "slack-user", approval_workflow: @workflow)
    NotificationSetting.create!(email_enabled: true, smtp_host: "smtp.example.com", mail_from: "gov@example.com")
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

  test "with email switched off, the workflow runs and no mail is enqueued" do
    NotificationSetting.current.update!(email_enabled: false)
    sign_in_as @requester
    assert_no_enqueued_emails do
      post "/access_requests", params: { role_id: @role.id, justification: "need it" }
    end
    access = Access.find_by!(user: @requester, role: @role)

    sign_in_as @manager
    assert_no_enqueued_emails do
      post "/approvals/#{access.id}/approve", params: { comment: "ok" }
    end
    assert_equal "approved", access.reload.status
  end

  test "with the messenger on, request, approval and denial each post to the channel" do
    NotificationSetting.current.update!(messenger_enabled: true, messenger_url: "https://hooks.example.com/x")
    other_role = Role.create!(application: @application, name: "Slack Admin", slug: "slack-admin", approval_workflow: @workflow)
    sign_in_as @requester

    assert_enqueued_with(job: Notifications::MessengerDeliveryJob) do
      post "/access_requests", params: { role_id: @role.id, justification: "on-call rotation" }
    end
    review = enqueued_jobs.select { |j| j["job_class"] == "Notifications::MessengerDeliveryJob" }.last["arguments"].first
    assert_equal "review_requested", review["event"]
    assert_equal @manager.name, review["approver"]
    assert_match "#{@requester.name} requested Slack User (Slack)", review["text"]
    assert_match "Awaiting approval from #{@manager.name}", review["text"]
    assert_match "Justification: on-call rotation", review["text"]
    assert_match %r{http://\S+/\z}, review["text"], "the message ends with a bare link"

    post "/access_requests", params: { role_id: other_role.id }
    access = Access.find_by!(user: @requester, role: @role)
    other = Access.find_by!(user: @requester, role: other_role)
    sign_in_as @manager

    clear_enqueued_jobs
    post "/approvals/#{access.id}/approve"
    approved = enqueued_jobs.find { |j| j["job_class"] == "Notifications::MessengerDeliveryJob" }["arguments"].first
    assert_equal "approved", approved["event"]
    assert_match "#{@requester.name} was granted Slack User (Slack).", approved["text"]

    clear_enqueued_jobs
    post "/approvals/#{other.id}/deny", params: { comment: "use the shared account" }
    denied = enqueued_jobs.find { |j| j["job_class"] == "Notifications::MessengerDeliveryJob" }["arguments"].first
    assert_equal "denied", denied["event"]
    assert_match "request for Slack Admin (Slack) was denied. Comment: use the shared account", denied["text"]
  end

  test "with the messenger off, nothing is posted" do
    sign_in_as @requester
    assert_no_enqueued_jobs only: Notifications::MessengerDeliveryJob do
      post "/access_requests", params: { role_id: @role.id }
    end
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
