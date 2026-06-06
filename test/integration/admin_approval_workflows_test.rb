require "test_helper"

class AdminApprovalWorkflowsTest < ActionDispatch::IntegrationTest
  def setup
    self_app = Application.create!(name: "Governauthzer", slug: Application::SELF_SLUG)
    operator_role = self_app.roles.create!(name: "Operator", slug: "operator", protected: true)
    @operator = User.create!(email: "op@example.com", name: "Op")
    Access.create!(user: @operator, role: operator_role, status: "approved", source: "manual")
    @alice = User.create!(email: "approver1@example.com", name: "Alice Approver")
    @bob   = User.create!(email: "approver2@example.com", name: "Bob Approver")
    sign_in_as @operator
  end

  test "operator creates a workflow and appends steps in order" do
    assert_difference([ "ApprovalWorkflow.count", "AuditEvent.where(event_type: 'approval_workflow.created').count" ], 1) do
      post "/admin/approval_workflows", params: { approval_workflow: { name: "Two step", slug: "two-step" } }
    end
    workflow = ApprovalWorkflow.find_by!(slug: "two-step")

    post "/admin/approval_workflows/#{workflow.id}/approval_steps",
         params: { approval_step: { strategy: "manager_of_requester", fallback_user_id: @alice.id } }
    post "/admin/approval_workflows/#{workflow.id}/approval_steps",
         params: { approval_step: { strategy: "named_user", approver_user_id: @bob.id, fallback_user_id: @alice.id } }

    steps = workflow.approval_steps.reload
    assert_equal [ 0, 1 ], steps.map(&:position)
    assert_equal "named_user", steps.last.strategy
    assert_equal @bob, steps.last.approver_user
  end

  test "named_user step requires a named approver" do
    workflow = ApprovalWorkflow.create!(name: "W", slug: "w")
    assert_no_difference("ApprovalStep.count") do
      post "/admin/approval_workflows/#{workflow.id}/approval_steps",
           params: { approval_step: { strategy: "named_user", approver_user_id: "", fallback_user_id: @alice.id } }
    end
    assert_response :unprocessable_content
  end

  test "operator edits and removes a step" do
    workflow = ApprovalWorkflow.create!(name: "W", slug: "w")
    step = workflow.approval_steps.create!(position: 0, strategy: "manager_of_requester", fallback_user: @alice)

    patch "/admin/approval_steps/#{step.id}",
          params: { approval_step: { strategy: "named_user", approver_user_id: @bob.id, fallback_user_id: @alice.id } }
    assert_equal "named_user", step.reload.strategy

    assert_difference("ApprovalStep.count", -1) do
      delete "/admin/approval_steps/#{step.id}"
    end
  end

  test "the default workflow cannot be deleted" do
    default = ApprovalWorkflow.create!(name: "Default", slug: ApprovalWorkflow::DEFAULT_SLUG)
    delete "/admin/approval_workflows/#{default.id}"
    assert_redirected_to "/admin/approval_workflows"
    assert ApprovalWorkflow.exists?(default.id)
  end

  test "a workflow with steps cannot be deleted" do
    workflow = ApprovalWorkflow.create!(name: "W", slug: "w")
    workflow.approval_steps.create!(position: 0, strategy: "manager_of_requester", fallback_user: @alice)
    assert_no_difference("ApprovalWorkflow.count") do
      delete "/admin/approval_workflows/#{workflow.id}"
    end
  end

  test "workflow and step pages render" do
    workflow = ApprovalWorkflow.create!(name: "W", slug: "w")
    step = workflow.approval_steps.create!(position: 0, strategy: "named_user", approver_user: @bob, fallback_user: @alice)

    get "/admin/approval_workflows";                    assert_response :ok
    get "/admin/approval_workflows/new";                assert_response :ok
    get "/admin/approval_workflows/#{workflow.id}";     assert_response :ok
    get "/admin/approval_workflows/#{workflow.id}/edit"; assert_response :ok
    get "/admin/approval_workflows/#{workflow.id}/approval_steps/new"; assert_response :ok
    get "/admin/approval_steps/#{step.id}/edit";        assert_response :ok
  end

  private

  def sign_in_as(user)
    raw = SecureRandom.urlsafe_base64(32)
    EmergencyToken.create!(user: user, token_digest: EmergencyToken.digest(raw),
                           reason: "test sign-in", expires_at: 5.minutes.from_now)
    get "/emergency-login/#{raw}"
  end
end
