class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens, id: :uuid do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at

      t.timestamps
    end

    add_index :api_tokens, :token_digest, unique: true
  end
end
