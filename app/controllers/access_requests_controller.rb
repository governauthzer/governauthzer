# Self-service request lifecycle from the end-user UI: create a request (which
# enters the role's approval workflow) and withdraw one's own pending request.
class AccessRequestsController < ApplicationController
  include AccessFlashMessages

  before_action :require_login!

  def create
    role = Role.find_by(id: params[:role_id])
    return redirect_to catalog_path, alert: "Select a role to request." if role.nil?

    result = Accesses::Requester.call(
      user: current_user, role: role, actor: current_user,
      justification: params[:justification].presence
    )

    if result.success
      redirect_to root_path, notice: granted_or_submitted(result.value)
    else
      redirect_to catalog_path, alert: access_flash(result.code)
    end
  end

  def destroy
    access = current_user.accesses.find(params[:id])
    decision = policy_for(access).withdraw?
    return redirect_to(root_path, alert: access_flash(decision.code)) unless decision.success

    Accesses::Withdrawer.call(access: access, actor: current_user)
    redirect_to root_path, notice: "Request withdrawn."
  end

  private

  def granted_or_submitted(access)
    access.approved? ? "Access granted." : "Request submitted for approval."
  end
end
