class ApprovalStep < ApplicationRecord
  STRATEGIES = %w[manager_of_requester named_user].freeze

  belongs_to :approval_workflow
  belongs_to :approver_user, class_name: "User", optional: true
  belongs_to :fallback_user, class_name: "User"
  has_many :approval_decisions, dependent: :restrict_with_error

  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :strategy, inclusion: { in: STRATEGIES }

  def resolve_approver(requester:)
    candidate = approver_candidate(requester)
    return candidate if valid_approver?(candidate, requester)
    valid_approver?(fallback_user, requester) ? fallback_user : nil
  end

  private

  def approver_candidate(requester)
    case strategy
    when "manager_of_requester" then requester&.manager
    when "named_user"           then approver_user
    end
  end

  def valid_approver?(user, requester)
    user.present? && user.active? && user != requester
  end
end
