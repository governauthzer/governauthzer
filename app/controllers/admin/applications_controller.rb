class Admin::ApplicationsController < Admin::BaseController
  before_action :find_application, only: %i[show edit update destroy]
  before_action :block_system_application!, only: %i[edit update destroy]

  def index
    @applications = Application.left_joins(:roles)
                              .select("applications.*, COUNT(roles.id) AS roles_count")
                              .group("applications.id")
                              .order(:name)
  end

  def show
    @roles = @application.roles.includes(:approval_workflow).order(:name)
  end

  def new
    @application = Application.new
  end

  def create
    @application = Application.new(application_params)
    if @application.save
      record_admin_audit("application.created", @application)
      redirect_to admin_application_path(@application), notice: "Application created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @application.assign_attributes(application_params)
    changes = @application.changes
    if @application.save
      record_admin_audit("application.updated", @application, attribute_changes: changes)
      redirect_to admin_application_path(@application), notice: "Application updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    snapshot = { "id" => @application.id, "slug" => @application.slug, "name" => @application.name }
    if @application.destroy
      record_admin_audit("application.deleted", @application, snapshot: snapshot)
      redirect_to admin_applications_path, notice: "Application deleted."
    else
      redirect_to admin_applications_path,
                  alert: "Cannot delete: #{@application.errors.full_messages.join('; ')}"
    end
  end

  private

  def find_application
    @application = Application.find(params[:id])
  end

  # The governauthzer-itself application underpins operator authorization (operator?
  # resolves roles by its slug), so it is system-managed and read-only in the UI.
  def block_system_application!
    return unless @application.itself?
    redirect_to admin_applications_path,
                alert: "The governauthzer application is system-managed and cannot be modified."
  end

  def application_params
    params.require(:application).permit(:name, :slug)
  end
end
