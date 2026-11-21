# The admin UI's "send test email": proves the SMTP settings work end to end,
# delivered synchronously so the operator sees the server's answer.
class NotificationTestMailer < ApplicationMailer
  def test_email
    @name = params[:name]
    mail to: params[:email], subject: "governauthzer test email"
  end
end
