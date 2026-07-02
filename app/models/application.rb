class Application < ApplicationRecord
  include Sluggable

  SELF_SLUG = "governauthzer".freeze

  has_many :roles, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, uniqueness: true

  def self.itself_record
    find_by(slug: SELF_SLUG)
  end

  def itself?
    slug == SELF_SLUG
  end
end
