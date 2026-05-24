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

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def self.find_by_raw_token(raw_token)
    find_by(token_digest: digest(raw_token))
  end

  def used?
    used_at.present?
  end

  def expired?
    expires_at <= Time.current
  end

  def redeemable?
    !used? && !expired?
  end

  # Atomic single-use claim. Returns true if this caller won the race.
  # Returns false if the token was already used or expired meanwhile.
  def claim!
    updated = self.class.where(id: id, used_at: nil)
                        .where("expires_at > ?", Time.current)
                        .update_all(used_at: Time.current)
    updated == 1
  end
end
