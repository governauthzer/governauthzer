class Api::V1::UsersByExternalIdController < Api::V1::BaseController
  include Api::UserParams

  def update
    user = lookup_user
    return render_external_identity_not_found unless user

    permitted = update_params
    result = Users::Updater.call(
      user: user,
      attrs: permitted.except(:manager_external_id).to_h.symbolize_keys,
      manager_external_id: extract_manager_external_id(permitted),
      actor: :system
    )

    if result.success
      render json: Api::V1::UserSerializer.new(result.value).as_json
    else
      render_service_failure(result)
    end
  end

  private

  def lookup_user
    normalized = ExternalIdentity.normalize_source(params[:source])
    ExternalIdentity.find_by(source: normalized, external_id: params[:external_id])&.user
  end

  def render_external_identity_not_found
    render_error(
      code: "external_identity_not_found",
      status: :not_found,
      message: "No user found for the given (source, external_id).",
      details: { "source" => params[:source], "external_id" => params[:external_id] }
    )
  end
end
