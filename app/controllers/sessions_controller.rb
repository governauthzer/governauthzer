class SessionsController < ApplicationController
  def destroy
    sign_out
    render :destroyed
  end
end
