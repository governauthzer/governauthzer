class WebhookDelivery < ApplicationRecord
  STATUSES = %w[pending delivered failed dead].freeze
  MAX_ATTEMPTS = 8

  belongs_to :webhook_subscription

  validates :audit_event_id, presence: true
  validates :cloud_event_type, presence: true
  validates :payload, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Rows whose (re)delivery job is presumed lost. The primary retry path is
  # DeliveryJob's self-re-enqueue, so anything still pending/failed well past its
  # due time has no live job behind it (worker died between the row update and the
  # enqueue, or the queue DB was purged/restored). `grace` keeps the sweeper from
  # racing a healthy-but-slightly-late scheduled retry into a duplicate POST.
  # Pending rows carry no next_retry_at — their due time is creation.
  scope :stuck, lambda { |grace:|
    cutoff = grace.ago
    where(status: "pending", created_at: ..cutoff)
      .or(where(status: "failed", next_retry_at: ..cutoff))
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
