class SnapshotRun < ApplicationRecord
  STATUSES = %w[applied dry_run rejected].freeze

  belongs_to :api_token

  validates :source, presence: true
  validates :as_of, presence: true
  validates :applied_at, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :payload_hash, presence: true
  validates :user_count, presence: true

  scope :applied, -> { where(status: "applied") }

  # Latest successfully-applied as_of for a source — drives staleness checks.
  def self.last_applied_as_of(source)
    applied.where(source: source).maximum(:as_of)
  end

  def audit_display
    "snapshot #{source}@#{as_of&.iso8601}"
  end
end
