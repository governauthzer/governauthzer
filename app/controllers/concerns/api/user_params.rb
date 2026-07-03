module Api::UserParams
  extend ActiveSupport::Concern

  # The user-attrs surface shared by the two write paths into Users::Updater
  # (UsersController and UsersByExternalIdController) — grow the permitted list
  # here so the controllers cannot drift apart.
  UPDATABLE_ATTRS = %i[email name status manager_id department title start_date end_date].freeze

  private

  def update_params
    params.require(:user).permit(
      *UPDATABLE_ATTRS,
      manager_external_id: %i[source external_id]
    )
  end

  # Distinguishes "field absent" (NOT_PROVIDED — leave the manager alone) from an
  # explicit null (clear the manager).
  def extract_manager_external_id(permitted)
    return ApplicationService::NOT_PROVIDED unless params[:user].key?(:manager_external_id)
    raw = permitted[:manager_external_id]
    return nil if raw.nil?
    raw.to_h.symbolize_keys
  end
end
