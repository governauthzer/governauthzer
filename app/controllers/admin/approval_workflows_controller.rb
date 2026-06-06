class Admin::ApprovalWorkflowsController < Admin::BaseController
  before_action :find_workflow, only: %i[show edit update destroy]
  before_action :block_default_destroy!, only: :destroy

  def index
    @workflows = ApprovalWorkflow.left_joins(:approval_steps, :roles)
                                 .select("approval_workflows.*, " \
                                         "COUNT(DISTINCT approval_steps.id) AS steps_count, " \
                                         "COUNT(DISTINCT roles.id) AS roles_count")
                                 .group("approval_workflows.id")
                                 .order(:name)
  end

  def show
    @steps = @workflow.approval_steps
  end

  def new
    @workflow = ApprovalWorkflow.new
  end

  def create
    @workflow = ApprovalWorkflow.new(workflow_params)
    if @workflow.save
      record_admin_audit("approval_workflow.created", @workflow)
      redirect_to admin_approval_workflow_path(@workflow), notice: "Workflow created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @workflow.assign_attributes(workflow_params)
    changes = @workflow.changes
    if @workflow.save
      record_admin_audit("approval_workflow.updated", @workflow, attribute_changes: changes)
      redirect_to admin_approval_workflow_path(@workflow), notice: "Workflow updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    snapshot = { "id" => @workflow.id, "slug" => @workflow.slug, "name" => @workflow.name }
    if @workflow.destroy
      record_admin_audit("approval_workflow.deleted", @workflow, snapshot: snapshot)
      redirect_to admin_approval_workflows_path, notice: "Workflow deleted."
    else
      redirect_to admin_approval_workflows_path,
                  alert: "Cannot delete: #{@workflow.errors.full_messages.join('; ')}"
    end
  end

  private

  def find_workflow
    @workflow = ApprovalWorkflow.find(params[:id])
  end

  # The default workflow is resolved implicitly by Access#workflow for any role
  # without an explicit workflow, so deleting it would break those requests.
  def block_default_destroy!
    return unless @workflow.slug == ApprovalWorkflow::DEFAULT_SLUG
    redirect_to admin_approval_workflows_path,
                alert: "The default workflow is used as a fallback and cannot be deleted."
  end

  def workflow_params
    params.require(:approval_workflow).permit(:name, :slug)
  end
end
