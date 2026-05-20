class ApprovalWorkflow < ApplicationRecord
  DEFAULT_SLUG = "default-manager".freeze

  has_many :approval_steps, -> { order(:position) }, dependent: :restrict_with_error
  has_many :roles, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :normalize_slug

  def self.default
    find_by!(slug: DEFAULT_SLUG)
  end

  private

  def normalize_slug
    return if slug.blank?
    self.slug = slug.downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-")
  end
end
