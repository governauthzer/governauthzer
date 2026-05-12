class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email, null: false
      t.string :name, null: false

      t.string :status, null: false, default: "pending_start"

      t.references :manager, type: :uuid, foreign_key: { to_table: :users }
      t.string :department
      t.string :title
      t.date :start_date
      t.date :end_date

      t.timestamps
    end

    add_index :users, :email, unique: true, where: "status <> 'terminated'"
    add_index :users, :status
  end
end
