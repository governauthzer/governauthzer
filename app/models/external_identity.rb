class ExternalIdentity < ApplicationRecord
  belongs_to :user

  validates :source, presence: true
  validates :external_id, presence: true
  validates :source, uniqueness: { scope: :external_id }

  before_validation :apply_source_normalization

  def self.normalize_source(raw)
    return nil if raw.blank?
    raw.downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-")
  end

  private

  def apply_source_normalization
    self.source = self.class.normalize_source(source)
  end
end
