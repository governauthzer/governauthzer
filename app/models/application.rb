class Application < ApplicationRecord
  SELF_SLUG = "governauthzer".freeze

  has_many :roles, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  before_validation :normalize_slug

  def self.itself_record
    find_by(slug: SELF_SLUG)
  end

  def itself?
    slug == SELF_SLUG
  end

  private

  def normalize_slug
    return if slug.blank?
    self.slug = slug.downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-")
  end
end
