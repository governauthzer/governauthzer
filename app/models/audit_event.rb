class AuditEvent < ApplicationRecord
  ACTOR_TYPES = %w[user system].freeze
  CURRENT_SCHEMA_VERSION = "1.0".freeze

  belongs_to :actor, class_name: "User", optional: true

  validates :event_type, presence: true
  validates :actor_type, inclusion: { in: ACTOR_TYPES }
  validates :correlation_id, presence: true
  validate :actor_id_matches_actor_type

  private

  def actor_id_matches_actor_type
    case actor_type
    when "user"
      errors.add(:actor_id, "must be set when actor_type is user") if actor_id.blank?
    when "system"
      errors.add(:actor_id, "must be blank when actor_type is system") if actor_id.present?
    end
  end
end
