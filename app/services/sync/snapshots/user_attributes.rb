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
    end
  end
end
