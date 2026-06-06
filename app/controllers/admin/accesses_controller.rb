class Admin::AccessesController < Admin::BaseController
  # Revoke a single granted access from the operator UI (e.g. the user detail page).
  def destroy
    access = Access.find(params[:id])
    user = access.user
    result = Accesses::Revoker.call(access: access, actor: current_user)
    if result.success
      redirect_to admin_user_path(user), notice: "Access revoked."
    else
      redirect_to admin_user_path(user), alert: "Only granted access can be revoked."
    end
  end
end
