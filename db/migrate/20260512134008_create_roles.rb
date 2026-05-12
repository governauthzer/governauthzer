class CreateRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :roles, id: :uuid do |t|
      t.references :application, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :protected, null: false, default: false

      t.timestamps
    end

    add_index :roles, [ :application_id, :slug ], unique: true
  end
end
