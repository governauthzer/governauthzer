# Notification wiring for the approval workflow, mixed into the access services. Each
# helper enqueues non-blocking notifications at a decision point: an email to the
# person concerned, and a post to the messenger channel. Reads happen at call time
# (before the deny path destroys the row), and only primitives are passed on. Nothing
# is enqueued for a channel that is switched off, so an install without notifications
# has no failing jobs.
module AccessNotifications
  private

  # The request now sits with an approver → ask them to review.
  def notify_review(access)
    approver = access.current_approver
    return if approver.nil?

    settings = NotificationSetting.current
    if settings.email_enabled?
      AccessMailer.with(
        email: approver.email, name: approver.name,
        requester_name: access.user.name,
        role_name: access.role.name,
        application_name: access.role.application.name,
        justification: access.justification
      ).review_request.deliver_later
    end

    post_to_messenger(settings, access, event: "review_requested", approver: approver.name,
                      text: "#{access.user.name} requested #{role_label(access)}. " \
                            "Awaiting approval from #{approver.name}." +
                            labelled(" Justification: ", access.justification))
  end

  # The request was granted → tell the subject.
  def notify_approved(access)
    settings = NotificationSetting.current
    if settings.email_enabled?
      AccessMailer.with(
        email: access.user.email, name: access.user.name,
        role_name: access.role.name,
        application_name: access.role.application.name
      ).request_approved.deliver_later
    end

    post_to_messenger(settings, access, event: "approved",
                      text: "#{access.user.name} was granted #{role_label(access)}.")
  end

  # The request was denied → tell the requester (read before the row is destroyed).
  def notify_denied(access, comment)
    settings = NotificationSetting.current
    requester = access.requested_by
    if settings.email_enabled? && requester
      AccessMailer.with(
        email: requester.email, name: requester.name,
        role_name: access.role.name,
        application_name: access.role.application.name,
        comment: comment
      ).request_denied.deliver_later
    end

    post_to_messenger(settings, access, event: "denied", comment: comment,
                      text: "#{access.user.name}'s request for #{role_label(access)} was denied." +
                            labelled(" Comment: ", comment))
  end

  # `text` is the ready-made message; the other fields are there for operators who
  # compose their own template. The link is bare, so every messenger renders it.
  def post_to_messenger(settings, access, event:, text:, approver: nil, comment: nil)
    return unless settings.messenger_enabled?

    link = Rails.application.routes.url_helpers.root_url
    Notifications::MessengerDeliveryJob.perform_later(
      "text" => "#{text}\n#{link}",
      "event" => event,
      "requester" => access.user.name,
      "role" => access.role.name,
      "application" => access.role.application.name,
      "approver" => approver.to_s,
      "justification" => access.justification.to_s,
      "comment" => comment.to_s,
      "link" => link
    )
  end

  def role_label(access)
    "#{access.role.name} (#{access.role.application.name})"
  end

  def labelled(label, value)
    value.present? ? "#{label}#{value}" : ""
  end
end
