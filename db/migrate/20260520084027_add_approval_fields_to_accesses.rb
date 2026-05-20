class AddApprovalFieldsToAccesses < ActiveRecord::Migration[8.1]
  def change
    change_table :accesses do |t|
      t.references :approved_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :approved_at
    end
  end
end
