# Approver inbox actions. Available to any signed-in active user (an approver may
# be a non-operator manager), so it sits behind require_login!, not the operator
# gate. Authorization is per-row via AccessPolicy (current approver only).
class ApprovalsController < ApplicationController
  include AccessFlashMessages

  before_action :require_login!
  before_action :set_access

  def approve
    decide(:approve?) do
      Accesses::Approver.call(access: @access, approver: current_user, actor: current_user, comment: comment)
    end
  end

  def deny
    decide(:deny?) do
      Accesses::Denier.call(access: @access, approver: current_user, actor: current_user, comment: comment)
    end
  end

  private

  def set_access
    @access = Access.find(params[:id])
  end

  def comment
    params[:comment].presence
  end

  def decide(permission)
    authorization = policy_for(@access).public_send(permission)
    return redirect_to(root_path, alert: access_flash(authorization.code)) unless authorization.success

    result = yield
    if result.success
      redirect_to root_path, notice: "Decision recorded."
    else
      redirect_to root_path, alert: access_flash(result.code)
    end
  end
end
