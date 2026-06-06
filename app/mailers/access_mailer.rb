# Approval-workflow notifications. All inputs arrive as primitive params via
# `.with(...)` (not AR records) so the mail survives a request row being destroyed
# (deny) and serializes cleanly for the queue.
class AccessMailer < ApplicationMailer
  def review_request
    @approver_name    = params[:name]
    @requester_name   = params[:requester_name]
    @role_name        = params[:role_name]
    @application_name = params[:application_name]
    @justification    = params[:justification]
    mail to: params[:email], subject: "Access request awaiting your approval"
  end

  def request_approved
    @name             = params[:name]
    @role_name        = params[:role_name]
    @application_name = params[:application_name]
    mail to: params[:email], subject: "Your access request was approved"
  end

  def request_denied
    @name             = params[:name]
    @role_name        = params[:role_name]
    @application_name = params[:application_name]
    @comment          = params[:comment]
    mail to: params[:email], subject: "Your access request was denied"
  end
end
