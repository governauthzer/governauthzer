require "test_helper"

class Accesses::WorkflowTest < ActiveSupport::TestCase
  def setup
    Current.correlation_id = SecureRandom.uuid
    @app = Application.create!(name: "Slack", slug: "slack")
    @manager = User.create!(email: "mgr@example.com", name: "Manager")
    @requester = User.create!(email: "req@example.com", name: "Requester", manager: @manager)
    @workflow = manager_workflow
    @role = Role.create!(application: @app, name: "Slack User", slug: "slack-user", approval_workflow: @workflow)
  end

  # ----- request -------------------------------------------------------------

  test "request creates a pending access routed to the requester's manager" do
    result = nil
    assert_difference("AuditEvent.where(event_type: 'access.requested').count", 1) do
      result = Accesses::Requester.call(user: @requester, role: @role, actor: @requester, justification: "need it")
    end

    assert result.success
    access = result.value
    assert_equal "pending", access.status
    assert_equal @requester, access.requested_by
    assert_equal @manager, access.current_approver
  end

  test "request for a protected role is refused (no self-request escalation)" do
    protected_role = Role.create!(application: @app, name: "Operator", slug: "operator",
                                  protected: true, approval_workflow: @workflow)
    result = Accesses::Requester.call(user: @requester, role: protected_role, actor: @requester)

    assert_not result.success
    assert_equal :role_protected, result.code
    assert_equal 0, Access.where(user: @requester, role: protected_role).count
  end

  test "request is rejected when an active access already exists" do
    Accesses::Requester.call(user: @requester, role: @role, actor: @requester)
    result = Accesses::Requester.call(user: @requester, role: @role, actor: @requester)

    assert_not result.success
    assert_equal :access_already_exists, result.code
  end

  test "request through a zero-step workflow is granted immediately" do
    auto = ApprovalWorkflow.create!(name: "Auto", slug: "auto-grant")
    role = Role.create!(application: @app, name: "Public", slug: "public", approval_workflow: auto)

    assert_difference("AuditEvent.where(event_type: 'access.approved').count", 1) do
      result = Accesses::Requester.call(user: @requester, role: role, actor: @requester)
      assert result.success
      assert_equal "approved", result.value.status
    end
  end

  test "request fails when no eligible approver can be resolved" do
    orphan_wf = ApprovalWorkflow.create!(name: "Stuck", slug: "stuck")
    # candidate nil (requester has no manager) and fallback == requester → invalid
    loner = User.create!(email: "loner@example.com", name: "Loner")
    orphan_wf.approval_steps.create!(position: 0, strategy: "manager_of_requester", fallback_user: loner)
    role = Role.create!(application: @app, name: "Stuck", slug: "stuck", approval_workflow: orphan_wf)

    result = Accesses::Requester.call(user: loner, role: role, actor: loner)
    assert_not result.success
    assert_equal :no_eligible_approver, result.code
    assert_equal 0, Access.where(user: loner, role: role).count, "must not persist a stuck request"
  end

  # ----- approve / deny ------------------------------------------------------

  test "approver approving a single-step request grants it" do
    access = pending_access

    assert_difference("AuditEvent.where(event_type: 'access.approved').count", 1) do
      result = Accesses::Approver.call(access: access, approver: @manager, actor: @manager, comment: "ok")
      assert result.success
    end

    assert_equal "approved", access.reload.status
    assert_equal 1, access.approval_decisions.approvals.count
  end

  test "approval of a multi-step request advances rather than granting" do
    second = User.create!(email: "vp@example.com", name: "VP")
    @workflow.approval_steps.create!(position: 1, strategy: "named_user", approver_user: second, fallback_user: second)
    access = pending_access

    assert_difference("AuditEvent.where(event_type: 'access.approval_recorded').count", 1) do
      Accesses::Approver.call(access: access, approver: @manager, actor: @manager)
    end
    assert_equal "pending", access.reload.status
    assert_equal second, access.current_approver

    assert_difference("AuditEvent.where(event_type: 'access.approved').count", 1) do
      Accesses::Approver.call(access: access, approver: second, actor: second)
    end
    assert_equal "approved", access.reload.status
  end

  test "approving by a non-current-approver is rejected" do
    access = pending_access
    result = Accesses::Approver.call(access: access, approver: @requester, actor: @requester)
    assert_not result.success
    assert_equal :not_current_approver, result.code
  end

  test "denial emits access.denied and destroys the request" do
    access = pending_access

    assert_difference("AuditEvent.where(event_type: 'access.denied').count", 1) do
      result = Accesses::Denier.call(access: access, approver: @manager, actor: @manager, comment: "no")
      assert result.success
    end
    assert_not Access.exists?(access.id)
  end

  # ----- withdraw ------------------------------------------------------------

  test "withdraw emits access.withdrawn and destroys the request" do
    access = pending_access

    assert_difference("AuditEvent.where(event_type: 'access.withdrawn').count", 1) do
      result = Accesses::Withdrawer.call(access: access, actor: @requester)
      assert result.success
    end
    assert_not Access.exists?(access.id)
  end

  # ----- policy --------------------------------------------------------------

  test "AccessPolicy authorizes only the current approver and the requester" do
    access = pending_access

    assert AccessPolicy.new(user: @manager, record: access).approve?.success
    assert_equal :not_current_approver, AccessPolicy.new(user: @requester, record: access).approve?.code

    assert AccessPolicy.new(user: @requester, record: access).withdraw?.success
    assert_equal :not_requester, AccessPolicy.new(user: @manager, record: access).withdraw?.code
  end

  private

  def manager_workflow
    wf = ApprovalWorkflow.create!(name: "Manager", slug: "mgr-flow")
    wf.approval_steps.create!(position: 0, strategy: "manager_of_requester", fallback_user: @manager)
    wf
  end

  def pending_access
    Accesses::Requester.call(user: @requester, role: @role, actor: @requester).value
  end
end
