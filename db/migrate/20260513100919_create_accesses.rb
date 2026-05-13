class CreateAccesses < ActiveRecord::Migration[8.1]
  def change
    create_table :accesses, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :role, type: :uuid, null: false, foreign_key: true
      t.references :requested_by, type: :uuid, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.text :justification
      t.datetime :expires_at

      t.timestamps
    end

    add_index :accesses, [ :user_id, :role_id ], unique: true
    add_index :accesses, :status
  end
end
