class CreateWebhookSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_subscriptions, id: :uuid do |t|
      t.string  :name, null: false
      t.string  :endpoint_url, null: false
      t.string  :signing_secret, null: false               # HMAC key for outbound delivery
      t.string  :event_types, array: true, null: false, default: []     # [] = all published types
      t.uuid    :application_ids, array: true, null: false, default: []  # [] = all applications
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :webhook_subscriptions, :active
  end
end
