class EmergencyToken < ApplicationRecord
  TTL = 10.minutes

  belongs_to :user
  belongs_to :issued_by, class_name: "User", optional: true

  validates :token_digest, presence: true, uniqueness: true
  validates :reason, presence: true
  validates :expires_at, presence: true

  scope :unused,  -> { where(used_at: nil) }
  scope :live,    -> { where("expires_at > ?", Time.current) }
  scope :active,  -> { unused.live }

  def used?
    used_at.present?
  end

  def expired?
    expires_at <= Time.current
  end

  def redeemable?
    !used? && !expired?
  end
end
