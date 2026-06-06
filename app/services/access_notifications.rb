# Mailer wiring for the approval workflow, mixed into the access services. Each
# helper enqueues a non-blocking notification (deliver_later) at a decision point.
# Reads happen at call time (before the deny path destroys the row), and only
# primitives are passed to the mailer.
module AccessNotifications
  private

  # The request now sits with an approver → ask them to review.
  def notify_review(access)
    approver = access.current_approver
    return if approver.nil?

    AccessMailer.with(
      email: approver.email, name: approver.name,
      requester_name: access.user.name,
      role_name: access.role.name,
      application_name: access.role.application.name,
      justification: access.justification
    ).review_request.deliver_later
  end

  # The request was granted → tell the subject.
  def notify_approved(access)
    AccessMailer.with(
      email: access.user.email, name: access.user.name,
      role_name: access.role.name,
      application_name: access.role.application.name
    ).request_approved.deliver_later
  end

  # The request was denied → tell the requester (read before the row is destroyed).
  def notify_denied(access, comment)
    requester = access.requested_by
    return if requester.nil?

    AccessMailer.with(
      email: requester.email, name: requester.name,
      role_name: access.role.name,
      application_name: access.role.application.name,
      comment: comment
    ).request_denied.deliver_later
  end
end
