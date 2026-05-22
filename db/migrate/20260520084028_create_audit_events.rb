class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events, id: :uuid do |t|
      t.datetime :occurred_at, null: false
      t.string :schema_version, null: false, default: "1.0"

      t.string :event_type, null: false

      t.string :actor_type, null: false
      t.references :actor, type: :uuid, foreign_key: { to_table: :users }
      t.string :actor_display

      t.jsonb :targets, null: false, default: []

      t.text :justification
      t.jsonb :attribute_changes

      t.inet :ip_address
      t.text :user_agent
      t.uuid :correlation_id, null: false

      t.jsonb :metadata
    end

    add_index :audit_events, :occurred_at, order: :desc
    add_index :audit_events, :event_type
    add_index :audit_events, [ :actor_id, :occurred_at ]
    add_index :audit_events, :correlation_id
    add_index :audit_events, :targets, using: :gin, opclass: :jsonb_path_ops
  end
end
