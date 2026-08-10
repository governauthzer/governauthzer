class AddUniqueIndexToApprovalDecisions < ActiveRecord::Migration[8.1]
  def change
    # One approval per step, enforced where every other uniqueness rule in this
    # schema is enforced: the database. Without it, two concurrent approvals of the
    # same step both pass the service's check-then-act guard, both insert, both see
    # the access as fully approved — two `access.approved` audit events, two
    # CloudEvents, and a bridge that grants twice.
    #
    # Partial on `approved`: a denial is terminal and destroys the access rather
    # than recording a row, but the `denied` value exists in the model, and nothing
    # about this invariant should constrain it.
    add_index :approval_decisions, [ :access_id, :approval_step_id ],
              unique: true,
              where: "decision = 'approved'",
              name: "index_approval_decisions_unique_approval_per_step"
  end
end
