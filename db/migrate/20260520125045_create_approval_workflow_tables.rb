class CreateApprovalWorkflowTables < ActiveRecord::Migration[8.1]
  def change
    create_table :approval_workflows, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :protected, null: false, default: false
      t.timestamps
    end
    add_index :approval_workflows, :slug, unique: true

    create_table :approval_steps, id: :uuid do |t|
      t.references :approval_workflow, type: :uuid, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :strategy, null: false
      t.references :approver_user, type: :uuid, foreign_key: { to_table: :users }
      t.references :fallback_user, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :approval_steps, [ :approval_workflow_id, :position ], unique: true

    create_table :approval_decisions, id: :uuid do |t|
      t.references :access, type: :uuid, null: false, foreign_key: true
      t.references :approval_step, type: :uuid, null: false, foreign_key: true
      t.references :approver, type: :uuid, null: false, foreign_key: { to_table: :users }
      t.string :decision, null: false
      t.text :comment
      t.timestamps
    end

    add_reference :roles, :approval_workflow, type: :uuid, foreign_key: true
  end
end
