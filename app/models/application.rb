class Application < ApplicationRecord
  include Sluggable

  SELF_SLUG = "governauthzer".freeze

  has_many :roles, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, uniqueness: true

  # The row representing governauthzer itself — operator roles hang off it.
  def self.self_app
    find_by(slug: SELF_SLUG)
  end

  def self_app?
    slug == SELF_SLUG
  end
end
