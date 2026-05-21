class CreateEmergencyTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :emergency_tokens, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.text :reason, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.references :issued_by, type: :uuid, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :emergency_tokens, :token_digest, unique: true
    add_index :emergency_tokens, [ :user_id, :used_at ]
  end
end
