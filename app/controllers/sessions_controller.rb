class SessionsController < ApplicationController
  def destroy
    sign_out
    redirect_to login_path, status: :see_other, notice: "You've been signed out."
  end
end
