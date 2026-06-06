class Admin::RolesController < Admin::BaseController
  before_action :find_application, only: %i[new create]
  before_action :find_role, only: %i[edit update destroy]
  before_action :block_system_application_role!

  def new
    @role = @application.roles.new
  end

  def create
    @role = @application.roles.new(role_params)
    if @role.save
      record_admin_audit("role.created", @role)
      redirect_to admin_application_path(@application), notice: "Role created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @role.assign_attributes(role_params)
    changes = @role.changes
    if @role.save
      record_admin_audit("role.updated", @role, attribute_changes: changes)
      redirect_to admin_application_path(@role.application), notice: "Role updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    application = @role.application
    snapshot = { "id" => @role.id, "slug" => @role.slug, "name" => @role.name, "application_id" => application.id }
    if @role.destroy
      record_admin_audit("role.deleted", @role, snapshot: snapshot)
      redirect_to admin_application_path(application), notice: "Role deleted."
    else
      redirect_to admin_application_path(application),
                  alert: "Cannot delete: #{@role.errors.full_messages.join('; ')}"
    end
  end

  private

  def find_application
    @application = Application.find(params[:application_id])
  end

  def find_role
    @role = Role.find(params[:id])
    @application = @role.application
  end

  # Roles on the governauthzer-itself application define operator status and are
  # bootstrap-managed (seed-admin / console), never via the UI.
  def block_system_application_role!
    return unless @application&.itself?
    redirect_to admin_applications_path,
                alert: "Roles on the governauthzer application are system-managed."
  end

  def role_params
    params.require(:role).permit(:name, :slug, :protected, :approval_workflow_id)
  end
end
