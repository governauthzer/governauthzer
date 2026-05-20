class Access < ApplicationRecord
  STATUSES = %w[pending approved].freeze

  belongs_to :user
  belongs_to :role
  belongs_to :requested_by, class_name: "User", optional: true
  has_many :approval_decisions, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :role_id }

  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def approved_by
    final_approval_decision&.approver
  end

  def approved_at
    final_approval_decision&.created_at
  end

  def workflow
    role.approval_workflow || ApprovalWorkflow.default
  end

  def current_step
    workflow.approval_steps.find do |step|
      !approval_decisions.approvals.exists?(approval_step: step)
    end
  end

  def current_approver
    current_step&.resolve_approver(requester: requested_by)
  end

  def fully_approved?
    current_step.nil?
  end

  def audit_display
    "#{user.name} → #{role.name}"
  end

  private

  def final_approval_decision
    approval_decisions
      .approvals
      .joins(:approval_step)
      .order("approval_steps.position DESC, approval_decisions.created_at DESC")
      .first
  end
end
