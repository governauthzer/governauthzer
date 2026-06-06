class Admin::ApprovalStepsController < Admin::BaseController
  before_action :find_workflow, only: %i[new create]
  before_action :find_step, only: %i[edit update destroy]

  def new
    @step = @workflow.approval_steps.new
  end

  def create
    @step = @workflow.approval_steps.new(step_params)
    @step.position = next_position
    if @step.save
      record_admin_audit("approval_step.created", @step)
      redirect_to admin_approval_workflow_path(@workflow), notice: "Step added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @step.assign_attributes(step_params)
    changes = @step.changes
    if @step.save
      record_admin_audit("approval_step.updated", @step, attribute_changes: changes)
      redirect_to admin_approval_workflow_path(@step.approval_workflow), notice: "Step updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    workflow = @step.approval_workflow
    snapshot = { "id" => @step.id, "position" => @step.position, "strategy" => @step.strategy }
    if @step.destroy
      record_admin_audit("approval_step.deleted", @step, snapshot: snapshot)
      redirect_to admin_approval_workflow_path(workflow), notice: "Step removed."
    else
      redirect_to admin_approval_workflow_path(workflow),
                  alert: "Cannot remove: #{@step.errors.full_messages.join('; ')}"
    end
  end

  private

  def find_workflow
    @workflow = ApprovalWorkflow.find(params[:approval_workflow_id])
  end

  def find_step
    @step = ApprovalStep.find(params[:id])
    @workflow = @step.approval_workflow
  end

  # Append at the end; reordering is a later enhancement (delete + re-add for now).
  def next_position
    (@workflow.approval_steps.maximum(:position) || -1) + 1
  end

  def step_params
    params.require(:approval_step).permit(:strategy, :approver_user_id, :fallback_user_id)
  end
end
