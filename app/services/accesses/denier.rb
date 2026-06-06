module Accesses
  # Denies a pending access at its current step. A denial is terminal: it emits
  # `access.denied` (the audit log captures approver, step and comment) and then
  # destroys the request row — there is no `denied` status, and the unique
  # (user_id, role_id) index would otherwise block a legitimate re-request.
  # Authorized via AccessPolicy#deny? by the caller.
  class Denier < ApplicationService
    include AccessNotifications

    def initialize(access:, approver:, actor:, comment: nil)
      @access = access
      @approver = approver
      @actor = actor
      @comment = comment
    end

    def call
      return failure(:not_current_approver) unless @access.pending? && @access.current_approver == @approver

      ActiveRecord::Base.transaction do
        AuditEvent.record!(
          event_type: "access.denied",
          actor: @actor,
          targets: [ @access.user, @access, @access.role ],
          justification: @comment,
          metadata: { "source" => "admin-ui", "via" => "approval", "step_position" => @access.current_step&.position }
        )
        notify_denied(@access, @comment)
        @access.destroy!
        success(@access)
      end
    end
  end
end
