module Accesses
  # Recurring job (hourly) that revokes time-bounded grants whose `expires_at` has
  # passed. Each expired approved access is revoked exactly like any other revoke
  # (emit-before-destroy `access.revoked`, then destroy the row — per the 2026-05-13
  # Access lock there is no `revoked` status). System actor; the `via`/`reason`
  # metadata distinguish expiry from operator-driven revocation in the audit log.
  class ExpirySweeper < ApplicationJob
    include AccessRevocation

    queue_as :default

    def perform
      Access.approved
            .where.not(expires_at: nil)
            .where(expires_at: ..Time.current)
            .includes(:user, :role)
            .find_each do |access|
        ActiveRecord::Base.transaction do
          revoke_access(
            access: access, actor: :system,
            source: "job", via: "expiry_sweeper", reason: "grant_expired"
          )
        end
      end
    end
  end
end
