# The simple, compact role catalog: roles the current user can still request
# (i.e. doesn't already hold or have pending). Requesting itself is handled by
# AccessRequestsController#create.
class CatalogController < ApplicationController
  before_action :require_login!

  def index
    held_role_ids = current_user.accesses.pluck(:role_id)
    @roles = Role.includes(:application)
                 .where(protected: false)
                 .where.not(id: held_role_ids)
                 .order(:name)
  end
end
