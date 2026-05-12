class Role < ApplicationRecord
  belongs_to :application
  has_many :user_roles, dependent: :restrict_with_error
  has_many :users, through: :user_roles

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :application_id }

  before_validation :normalize_slug

  def operator_role?
    application.itself?
  end

  private

  def normalize_slug
    return if slug.blank?
    self.slug = slug.downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-")
  end
end
