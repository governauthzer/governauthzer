module Accesses
  # Operator-driven revoke of a single granted access (vs terminating the whole
  # user). Emit-before-destroy `access.revoked` then destroy, via the shared
  # AccessRevocation path. Audit-only — no email, consistent with every other
  # revoke path (orphan cascade, termination, expiry sweeper). Only approved
  # grants are revocable; pending requests are withdrawn/denied instead.
  class Revoker < ApplicationService
    include AccessRevocation

    def initialize(access:, actor:, reason: "operator_revoked")
      @access = access
      @actor = actor
      @reason = reason
    end

    def call
      return failure(:not_approved) unless @access.approved?

      ActiveRecord::Base.transaction do
        revoke_access(access: @access, actor: @actor, source: "admin-ui", via: "operator_revoke", reason: @reason)
      end
      success(@access)
    end
  end
end
