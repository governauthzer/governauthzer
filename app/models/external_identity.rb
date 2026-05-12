class ExternalIdentity < ApplicationRecord
  belongs_to :user

  validates :source, presence: true
  validates :external_id, presence: true
  validates :source, uniqueness: { scope: :external_id }

  before_validation :normalize_source

  private

  def normalize_source
    return if source.blank?
    self.source = source.downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-")
  end
end
