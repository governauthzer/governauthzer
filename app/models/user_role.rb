class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role

  validates :user_id, uniqueness: { scope: :role_id }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end
