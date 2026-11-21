class ApplicationMailer < ActionMailer::Base
  # Sender and SMTP server come from the operator's notification settings, read when
  # the message is built — inside the delivery job — so a settings change applies to
  # the next message without a restart. Only an :smtp delivery takes the server
  # settings; development's letter_opener and the test adapter keep their own.
  default from: -> { notification_settings.mail_from }
  default delivery_method_options: -> { smtp_delivery? ? notification_settings.smtp_settings : {} }
  layout "mailer"

  private

  def notification_settings
    @notification_settings ||= NotificationSetting.current
  end

  def smtp_delivery?
    self.class.delivery_method == :smtp
  end
end
