class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens, id: :uuid do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at

      # NULL source = full-access management token (default).
      # Non-NULL source = HRIS-sync token locked to exactly one source. The
      # snapshot endpoint derives its source from the token, never from the
      # body (Decision 1 in snapshot-sync-design: token scope is the auth
      # boundary — a bamboo-scoped token physically can't post into workday).
      t.string :source

      t.timestamps
    end

    add_index :api_tokens, :token_digest, unique: true
    add_index :api_tokens, :source, where: "source IS NOT NULL"
  end
end
