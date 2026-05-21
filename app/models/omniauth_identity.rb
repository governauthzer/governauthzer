class OmniauthIdentity < ApplicationRecord
  belongs_to :user
  belongs_to :auth_provider

  validates :subject, presence: true, uniqueness: { scope: :auth_provider_id }
end
