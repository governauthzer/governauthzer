class ApprovalWorkflow < ApplicationRecord
  has_many :approval_steps, -> { order(:position) }, dependent: :restrict_with_error
  has_many :roles, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :normalize_slug

  private

  def normalize_slug
    return if slug.blank?
    self.slug = slug.downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-")
  end
end
