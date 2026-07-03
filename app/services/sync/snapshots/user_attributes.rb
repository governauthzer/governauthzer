module Sync
  module Snapshots
    # Shared helpers for translating a snapshot user payload into User attributes.
    # `external_id` and `manager_external_id` are routing keys, not attributes.
    module UserAttributes
      ASSIGNABLE = %i[email name status department title start_date end_date].freeze

      # Attributes to assign on create/update. Status is dropped when blank so the
      # model's compute_initial_status can derive it from start_date.
      def assignable_attrs(payload)
        attrs = ASSIGNABLE.each_with_object({}) do |key, h|
          h[key] = payload[key] if payload.key?(key)
        end
        attrs.delete(:status) if attrs[:status].blank?
        attrs
      end

      # Assigns the payload onto the (unsaved) user and returns the would-be diff.
      # The one definition of "does this snapshot row change the user": dry-run
      # counts these diffs, apply persists them — sharing it keeps the two from
      # disagreeing.
      def stage_snapshot_changes(user, payload)
        user.assign_attributes(assignable_attrs(payload))
        user.changes
      end
    end
  end
end
