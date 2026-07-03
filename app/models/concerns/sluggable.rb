module Sluggable
  extend ActiveSupport::Concern

  # The one canonical slug normalizer ("SAP Production" → "sap-production").
  # Also reused for slug-shaped non-slug columns (`external_identities.source`,
  # via ExternalIdentity.normalize_source) so sources and slugs stay comparable.
  def self.normalize(raw)
    return nil if raw.blank?
    raw.downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-")
  end

  included do
    validates :slug, presence: true
    normalizes :slug, with: ->(raw) { Sluggable.normalize(raw) }
  end
end
