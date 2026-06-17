class WebhookDelivery < ApplicationRecord
  STATUSES = %w[pending delivered failed dead].freeze
  MAX_ATTEMPTS = 8

  belongs_to :webhook_subscription

  validates :audit_event_id, presence: true
  validates :cloud_event_type, presence: true
  validates :payload, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Rows ready for a (re)delivery attempt: never-delivered or transiently-failed,
  # and past their scheduled retry time (NULL = due now).
  scope :deliverable, lambda {
    where(status: %w[pending failed])
      .where("next_retry_at IS NULL OR next_retry_at <= ?", Time.current)
  }

  def delivered?
    status == "delivered"
  end

  def dead?
    status == "dead"
  end

  # Exponential backoff: 2^attempt minutes, capped at 6h. attempt_count is the
  # number of attempts already made, so the first retry waits 2^1 minutes.
  def backoff_delay
    [ 2**attempt_count, 360 ].min.minutes
  end
end
