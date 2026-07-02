class ApprovalWorkflow < ApplicationRecord
  include Sluggable

  DEFAULT_SLUG = "default-manager".freeze

  has_many :approval_steps, -> { order(:position) }, dependent: :restrict_with_error
  has_many :roles, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, uniqueness: true

  def self.default
    find_by!(slug: DEFAULT_SLUG)
  end
end
