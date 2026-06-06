class Admin::UsersController < Admin::BaseController
  before_action :find_user, only: %i[show update]

  def index
    @users = User.includes(:manager).order(:name)
    @users = @users.where(status: params[:status]) if User::STATUSES.include?(params[:status])
    @status = params[:status]
  end

  def show
    @approved = @user.accesses.approved.includes(role: :application)
    @pending = @user.accesses.pending.includes(role: :application)
    @external_identities = @user.external_identities.order(:source)
    @omniauth_identities = @user.omniauth_identities.includes(:auth_provider)
    @providers = AuthProvider.enabled.order(:name)
    @allowed_status_targets = (User::TRANSITIONS.fetch(@user.status, []) - %w[orphaned])
  end

  # Status transitions only — user attributes are HRIS-owned. Routes through the
  # same Users::Updater as the sync API (so the termination cascade / session
  # bump / audit all fire), but tagged with the admin-ui channel.
  def update
    result = Users::Updater.call(
      user: @user,
      attrs: { status: params.dig(:user, :status) },
      actor: current_user,
      source: "admin-ui"
    )
    if result.success
      redirect_to admin_user_path(@user), notice: "User updated."
    else
      redirect_to admin_user_path(@user), alert: status_error(result.code)
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_user_path(@user), alert: e.record.errors.full_messages.join("; ")
  end

  private

  def find_user
    @user = User.find(params[:id])
  end

  def status_error(code)
    case code
    when :reactivation_required then "Terminated users cannot be reactivated from here."
    else "Could not update the user."
    end
  end
end
