class CreateWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_deliveries, id: :uuid do |t|
      t.references :webhook_subscription, type: :uuid, null: false, foreign_key: true
      t.references :audit_event, type: :uuid, null: false, foreign_key: true # = CloudEvent id
      t.string   :cloud_event_type, null: false        # denormalized for querying
      t.jsonb    :payload, null: false                 # rendered CloudEvent, frozen for byte-stable retries
      t.string   :status, null: false, default: "pending" # pending | delivered | failed | dead
      t.integer  :attempt_count, null: false, default: 0
      t.integer  :last_response_code
      t.text     :last_error
      t.datetime :next_retry_at
      t.datetime :delivered_at

      t.timestamps
    end

    # One delivery row per (subscription, event) — makes fan-out idempotent.
    add_index :webhook_deliveries, [ :webhook_subscription_id, :audit_event_id ], unique: true,
              name: "index_webhook_deliveries_on_subscription_and_event"
    # The retry sweeper finds due rows by (status, next_retry_at).
    add_index :webhook_deliveries, [ :status, :next_retry_at ]
  end
end
