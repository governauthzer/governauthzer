# L4 per-row authorization for access requests. Approving/denying is restricted to
# the request's current approver; withdrawing to the requester. All gated on the
# request still being pending.
class AccessPolicy < ApplicationPolicy
  def approve?
    current_approver_decision
  end

  def deny?
    current_approver_decision
  end

  def withdraw?
    return deny(:not_pending) unless record.pending?
    return deny(:not_requester) unless record.requested_by_id == user&.id
    allow
  end

  private

  def current_approver_decision
    return deny(:not_pending) unless record.pending?
    return deny(:not_current_approver) unless record.current_approver == user
    allow
  end
end
