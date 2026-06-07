# Operator landing page. Replaces the old redirect-to-applications with an
# at-a-glance overview: outstanding approvals, the user population by status,
# catalog size, and recent audit activity — each linking into the CRUD surface
# that owns it.
class Admin::DashboardController < Admin::BaseController
  RECENT_EVENT_LIMIT = 12

  def index
    @pending_approvals = Access.pending.count
    @users_by_status = User.group(:status).count
    @users_total = @users_by_status.values.sum
    @applications_count = Application.count
    @roles_count = Role.count
    @recent_events = AuditEvent.order(occurred_at: :desc).limit(RECENT_EVENT_LIMIT)
  end
end
