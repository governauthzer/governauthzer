class User < ApplicationRecord
  STATUSES = %w[pending_start active suspended terminated].freeze

  belongs_to :manager, class_name: "User", optional: true

  validates :email, presence: true
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  def pending_start?
    status == "pending_start"
  end

  def active?
    status == "active"
  end

  def suspended?
    status == "suspended"
  end

  def terminated?
    status == "terminated"
  end
end
