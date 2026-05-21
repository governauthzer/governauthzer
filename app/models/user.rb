class User < ApplicationRecord
  STATUSES = %w[pending_start active suspended terminated].freeze

  belongs_to :manager, class_name: "User", optional: true
  has_many :external_identities, dependent: :restrict_with_error
  has_many :omniauth_identities, dependent: :restrict_with_error
  has_many :emergency_tokens, dependent: :restrict_with_error
  has_many :accesses, dependent: :restrict_with_error
  has_many :roles, through: :accesses

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

  def employee_id(source:)
    external_identities.find_by(source: source)&.external_id
  end

  def operator?
    accesses.approved.joins(role: :application)
            .where(applications: { slug: Application::SELF_SLUG }).exists?
  end
end
