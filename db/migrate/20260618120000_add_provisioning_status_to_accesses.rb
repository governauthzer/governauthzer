class AddProvisioningStatusToAccesses < ActiveRecord::Migration[8.1]
  def change
    # not_required = no provisioner is expected to fulfill this grant (standalone
    # core, or an application with no matching webhook subscription). Flipped to
    # `pending` when fan-out actually sends the grant to a subscriber, then to
    # applied/failed by the reconciliation callback.
    add_column :accesses, :provisioning_status, :string, null: false, default: "not_required"
  end
end
