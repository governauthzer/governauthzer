class Admin::BaseController < ApplicationController
  before_action :require_operator!

  private

  def require_operator!
    return if current_user&.operator?
    render "admin/forbidden", status: :forbidden
  end
end
