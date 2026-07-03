class Api::V1::UsersController < Api::V1::BaseController
  include Api::UserParams

  before_action :find_user, only: %i[show update destroy]

  SORT_WHITELIST = %w[created_at updated_at email name status].freeze

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
      attrs: extract_attrs(permitted).symbolize_keys,
      external_identities: nested_array(permitted[:external_identities]),
      omniauth_identities: nested_array(permitted[:omniauth_identities]),
      manager_external_id: extract_manager_external_id(permitted),
      actor: :system
    )

    if result.success
      render json: Api::V1::UserSerializer.new(result.value).as_json, status: :created
    else
      render_service_failure(result)
    end
  end

  def update
    permitted = update_params
    result = Users::Updater.call(
      user: @user,
      attrs: extract_attrs(permitted).symbolize_keys,
      manager_external_id: extract_manager_external_id(permitted),
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
      *Api::UserParams::UPDATABLE_ATTRS,
      external_identities: %i[source external_id],
      omniauth_identities: %i[auth_provider_slug subject],
      manager_external_id: %i[source external_id]
    )
  end

  def extract_attrs(permitted)
    permitted.except(:external_identities, :omniauth_identities, :manager_external_id).to_h
  end

  def nested_array(param)
    (param || []).map { |entry| entry.to_h.symbolize_keys }
  end
end
