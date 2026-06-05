class CreateSnapshotRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :snapshot_runs, id: :uuid do |t|
      t.string :source, null: false          # 'workday', 'bamboo', … (from token scope)
      t.datetime :as_of, null: false          # client-asserted snapshot timestamp
      t.datetime :applied_at, null: false     # server apply timestamp
      t.string :status, null: false           # 'applied' | 'dry_run' | 'rejected'
      t.string :payload_hash, null: false     # sha256 of users payload — duplicate detection
      t.integer :user_count, null: false      # = expected_count
      t.jsonb :diff_summary, null: false, default: {}
      t.references :api_token, type: :uuid, null: false, foreign_key: true
      t.jsonb :warnings, null: false, default: []

      t.timestamps
    end

    # Prevents two applied snapshots claiming the same (source, as_of) at the DB
    # level. Partial: only 'applied' rows occupy the slot — dry-runs and rejects
    # don't block a later real apply at the same as_of.
    add_index :snapshot_runs, [ :source, :as_of ], unique: true, where: "status = 'applied'"
    add_index :snapshot_runs, [ :source, :applied_at ]
  end
end
