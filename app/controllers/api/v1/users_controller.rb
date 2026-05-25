class Api::V1::UsersController < Api::V1::BaseController
  before_action :find_user, only: %i[show update destroy]

  SORT_WHITELIST = %w[created_at updated_at email name status].freeze

  ERROR_MAPPING = {
    unknown_auth_provider_slug: {
      status: :unprocessable_content,
      code: "unknown_auth_provider_slug",
      message: "Unknown auth_provider_slug."
    },
    external_id_collision: {
      status: :conflict,
      code: "external_id_collision",
      message: "External identity already linked to another user."
    },
    omniauth_identity_collision: {
      status: :conflict,
      code: "omniauth_identity_collision",
      message: "OmniAuth identity already linked to another user."
    },
    reactivation_required: {
      status: :unprocessable_content,
      code: "reactivation_required",
      message: "User is terminated; reactivation requires the explicit reactivation flow."
    }
  }.freeze

  def index
    scope = filtered_scope
    sorted = apply_default_sort(apply_sort(scope, whitelist: SORT_WHITELIST))
    render json: Api::V1::UserSerializer.collection(paginate(sorted))
  end

  def show
    render json: Api::V1::UserSerializer.new(@user).as_json
  end

  def create
    permitted = create_params
    result = Users::Creator.call(
      attrs: permitted.except(:external_identities, :omniauth_identities).to_h.symbolize_keys,
      external_identities: nested_array(permitted[:external_identities]),
      omniauth_identities: nested_array(permitted[:omniauth_identities]),
      actor: :system
    )

    if result.success
      render json: Api::V1::UserSerializer.new(result.value).as_json, status: :created
    else
      render_service_failure(result)
    end
  end

  def update
    result = Users::Updater.call(
      user: @user,
      attrs: update_params.to_h.symbolize_keys,
      actor: :system
    )

    if result.success
      render json: Api::V1::UserSerializer.new(result.value).as_json
    else
      render_service_failure(result)
    end
  end

  def destroy
    render_error(
      code: "method_not_allowed",
      status: :method_not_allowed,
      message: "Users cannot be deleted via API; use PATCH status=terminated. GDPR erasure has a separate endpoint."
    )
  end

  private

  def find_user
    @user = User.find(params[:id])
  end

  def filtered_scope
    scope = User.includes(
      :external_identities,
      { omniauth_identities: :auth_provider },
      { accesses: { role: :application } }
    )
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(manager_id: params[:manager_id]) if params[:manager_id].present?
    scope = scope.where(department: params[:department]) if params[:department].present?
    scope
  end

  def apply_default_sort(scope)
    return scope if params[:sort].present?
    scope.order(created_at: :desc)
  end

  def create_params
    params.require(:user).permit(
      :email, :name, :status, :manager_id, :department, :title, :start_date, :end_date,
      external_identities: %i[source external_id],
      omniauth_identities: %i[auth_provider_slug subject]
    )
  end

  def update_params
    params.require(:user).permit(
      :email, :name, :status, :manager_id, :department, :title, :start_date, :end_date
    )
  end

  def nested_array(param)
    (param || []).map { |entry| entry.to_h.symbolize_keys }
  end

  def render_service_failure(result)
    spec = ERROR_MAPPING.fetch(result.code)
    render_error(
      code: spec[:code],
      status: spec[:status],
      message: spec[:message],
      details: result.context
    )
  end
end
