class CreateOmniauthIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :omniauth_identities, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :auth_provider, type: :uuid, null: false, foreign_key: true
      t.string :subject, null: false

      t.timestamps
    end

    add_index :omniauth_identities, [ :auth_provider_id, :subject ], unique: true
  end
end
