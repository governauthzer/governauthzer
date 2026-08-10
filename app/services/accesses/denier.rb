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
      ActiveRecord::Base.transaction do
        # Same reasoning as Accesses::Approver: decide under the row lock, so a denial
        # racing an approval or a withdrawal resolves to one outcome rather than two.
        @access.lock!
        next failure(:not_current_approver) unless @access.pending? && @access.current_approver == @approver

        AuditEvent.record!(
          event_type: "access.denied",
          actor: @actor,
          targets: [ @access.user, @access, @access.role ],
          justification: @comment,
          metadata: { "source" => "web-ui", "via" => "approval", "step_position" => @access.current_step&.position }
        )
        notify_denied(@access, @comment)
        @access.destroy!
        success(@access)
      end
    rescue ActiveRecord::RecordNotFound
      failure(:no_longer_exists)
    end
  end
end
