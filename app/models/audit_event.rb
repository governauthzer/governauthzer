class AuditEvent < ApplicationRecord
  ACTOR_TYPES = %w[user system].freeze
  CURRENT_SCHEMA_VERSION = "1.0".freeze

  belongs_to :actor, class_name: "User", optional: true

  validates :event_type, presence: true
  validates :actor_type, inclusion: { in: ACTOR_TYPES }
  validates :correlation_id, presence: true
  validate :actor_id_matches_actor_type

  def self.record!(event_type:, actor:, targets: [], justification: nil, changes: nil, metadata: nil)
    create!(
      occurred_at: Time.current,
      schema_version: CURRENT_SCHEMA_VERSION,
      event_type: event_type,
      actor_type: actor == :system ? "system" : "user",
      actor_id: actor == :system ? nil : actor.id,
      actor_display: actor == :system ? nil : actor.audit_display,
      targets: Array(targets).map { |t| target_descriptor(t) },
      justification: justification,
      changes: changes,
      ip_address: Current.ip_address,
      user_agent: Current.user_agent,
      correlation_id: Current.correlation_id,
      metadata: metadata
    )
  end

  def self.target_descriptor(record)
    { "type" => record.class.name, "id" => record.id, "display" => record.audit_display }
  end

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
