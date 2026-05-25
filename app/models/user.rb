class User < ApplicationRecord
  STATUSES = %w[pending_start active suspended terminated].freeze

  TRANSITIONS = {
    "pending_start" => %w[active terminated],
    "active" => %w[suspended terminated],
    "suspended" => %w[active terminated],
    "terminated" => []
  }.freeze

  belongs_to :manager, class_name: "User", optional: true
  has_many :external_identities, dependent: :restrict_with_error
  has_many :omniauth_identities, dependent: :restrict_with_error
  has_many :emergency_tokens, dependent: :restrict_with_error
  has_many :accesses, dependent: :restrict_with_error
  has_many :roles, through: :accesses

  before_validation :compute_initial_status, on: :create

  validates :email, presence: true
  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :status_transition_legal, on: :update

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

  private

  def compute_initial_status
    return if status_changed?
    self.status = if start_date.nil? || start_date <= Date.current
                    "active"
    else
                    "pending_start"
    end
  end

  def status_transition_legal
    return unless status_changed?
    allowed = TRANSITIONS.fetch(status_was, [])
    return if allowed.include?(status)
    errors.add(:status, "cannot transition from '#{status_was}' to '#{status}'")
  end
end
