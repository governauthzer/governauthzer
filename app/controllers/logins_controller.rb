class LoginsController < ApplicationController
  def show
    @auth_providers = AuthProvider.enabled.order(:name)
  end
end
