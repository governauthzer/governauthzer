class CreateAuthProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :auth_providers, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :enabled, null: false, default: true
      t.string :oidc_issuer_url, null: false
      t.string :oidc_client_id, null: false
      t.string :oidc_client_secret
      t.string :oidc_scope, null: false, default: "openid email profile"
      t.jsonb :claim_mappings, null: false, default: []

      t.timestamps
    end

    add_index :auth_providers, :slug, unique: true
    add_index :auth_providers, :enabled
  end
end
