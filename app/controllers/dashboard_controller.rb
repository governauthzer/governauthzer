# Root of the minimalist end-user UI. Every signed-in active user lands here
# (operators too — they additionally get an Admin link). Shows the three things a
# person cares about: what's awaiting their approval, their own pending requests,
# and the roles they currently hold.
class DashboardController < ApplicationController
  before_action :require_login!

  def index
    @inbox = Access.pending
                   .includes(:user, :requested_by, role: :application)
                   .select { |access| access.current_approver == current_user }
    @my_requests = current_user.accesses.pending.includes(role: :application).order(created_at: :desc)
    @my_roles = current_user.accesses.approved.includes(role: :application).order(created_at: :desc)
  end
end
