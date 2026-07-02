module Accesses
  # Records an approval decision for the access's current step by its current
  # approver. On the final step (fully_approved?) the access is granted (status
  # approved) and emits `access.approved`; intermediate steps emit
  # `access.approval_recorded` and leave the access pending for the next approver.
  # The caller (controller) is expected to have authorized via AccessPolicy#approve?.
  class Approver < ApplicationService
    include AccessNotifications

    def initialize(access:, approver:, actor:, comment: nil)
      @access = access
      @approver = approver
      @actor = actor
      @comment = comment
    end

    def call
      return failure(:not_current_approver) unless approvable?

      step = @access.current_step
      ActiveRecord::Base.transaction do
        @access.approval_decisions.create!(approval_step: step, approver: @approver, decision: "approved", comment: @comment)
        if @access.fully_approved?
          grant
          notify_approved(@access)
        else
          record_step(step)
          notify_review(@access)
        end
        success(@access)
      end
    end

    private

    def approvable?
      @access.pending? && @access.current_approver == @approver
    end

    def grant
      @access.update!(status: "approved")
      AuditEvent.record!(
        event_type: "access.approved",
        actor: @actor,
        targets: [ @access.user, @access, @access.role ],
        justification: @comment,
        metadata: { "source" => "web-ui", "via" => "approval", "decision_method" => "workflow" }
      )
    end

    def record_step(step)
      AuditEvent.record!(
        event_type: "access.approval_recorded",
        actor: @actor,
        targets: [ @access.user, @access, @access.role ],
        justification: @comment,
        metadata: { "source" => "web-ui", "via" => "approval", "step_position" => step.position }
      )
    end
  end
end
