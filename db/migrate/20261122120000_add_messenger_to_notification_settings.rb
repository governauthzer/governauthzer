class AddMessengerToNotificationSettings < ActiveRecord::Migration[8.1]
  # The second notification channel: one incoming-webhook URL plus a JSON body
  # template, which covers Slack, Mattermost, Teams, Discord, Google Chat and
  # Telegram without code per messenger. The last_* columns are the channel's
  # current health, shown to the operator — a revoked webhook otherwise fails
  # silently for weeks.
  def change
    change_table :notification_settings, bulk: true do |t|
      t.boolean  :messenger_enabled, null: false, default: false
      t.text     :messenger_url
      t.text     :messenger_template, null: false, default: '{"text": "{{text}}"}'
      t.integer  :messenger_last_response_code
      t.text     :messenger_last_error
      t.datetime :messenger_last_attempted_at
    end
  end
end
