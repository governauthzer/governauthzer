class CreateApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :applications, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :applications, :slug, unique: true
  end
end
