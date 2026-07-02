class ExternalIdentity < ApplicationRecord
  belongs_to :user

  validates :source, presence: true
  validates :external_id, presence: true
  validates :source, uniqueness: { scope: :external_id }

  before_validation :apply_source_normalization

  # `source` is slug-shaped by convention (so it stays comparable with role and
  # application slugs); the actual rule lives in Sluggable.normalize. This method
  # stays as the public entry point — ApiToken and the sync/user services call it.
  def self.normalize_source(raw)
    Sluggable.normalize(raw)
  end

  def audit_display
    "#{source}/#{external_id}"
  end

  private

  def apply_source_normalization
    self.source = self.class.normalize_source(source)
  end
end
