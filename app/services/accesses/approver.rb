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
      ActiveRecord::Base.transaction do
        # Lock first, then decide. Read outside the lock, `approvable?` and
        # `fully_approved?` are check-then-act: two concurrent approvals of the same
        # step both pass, both insert, and both reach `grant` — two `access.approved`
        # audit events, two CloudEvents, a double grant on the target. The row lock
        # serializes them; the partial unique index on approval_decisions is the
        # backstop if a future path forgets to take it.
        @access.lock!
        next failure(:not_current_approver) unless approvable?

        step = @access.current_step
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
      # Denial and withdrawal destroy the row, so the request can vanish between the
      # controller's find and this lock.
    rescue ActiveRecord::RecordNotFound
      failure(:no_longer_exists)
    rescue ActiveRecord::RecordNotUnique
      failure(:already_decided)
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
