class Access < ApplicationRecord
  STATUSES = %w[pending approved].freeze

  belongs_to :user
  belongs_to :role
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true

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

  def audit_display
    "#{user.name} → #{role.name}"
  end
end
