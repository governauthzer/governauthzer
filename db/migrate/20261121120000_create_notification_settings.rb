class CreateNotificationSettings < ActiveRecord::Migration[8.1]
  # One row per installation: how governauthzer tells people that something needs
  # them. Kept in the database rather than ENV so an operator can set it up, test it
  # and change it from the admin UI without a redeploy; the SMTP password is
  # encrypted at rest like every other credential the app holds.
  def change
    create_table :notification_settings, id: :uuid do |t|
      # Guards the one-row shape: the unique index allows a single `true`, and the
      # check constraint forbids anything else.
      t.boolean :singleton, null: false, default: true

      t.boolean :email_enabled, null: false, default: false
      t.string  :smtp_host
      t.integer :smtp_port, null: false, default: 587
      t.string  :smtp_security, null: false, default: "starttls"
      t.string  :smtp_username
      t.text    :smtp_password
      t.string  :mail_from

      t.timestamps
    end

    add_index :notification_settings, :singleton, unique: true
    add_check_constraint :notification_settings, "singleton", name: "notification_settings_single_row"
  end
end
