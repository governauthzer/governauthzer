class ApprovalDecision < ApplicationRecord
  DECISIONS = %w[approved denied].freeze

  belongs_to :access
  belongs_to :approval_step
  belongs_to :approver, class_name: "User"

  validates :decision, inclusion: { in: DECISIONS }
end
