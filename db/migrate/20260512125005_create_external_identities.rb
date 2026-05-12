class CreateExternalIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :external_identities, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :source, null: false
      t.string :external_id, null: false

      t.timestamps
    end

    add_index :external_identities, [ :source, :external_id ], unique: true
  end
end
