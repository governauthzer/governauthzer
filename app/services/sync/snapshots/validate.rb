module Sync
  module Snapshots
    # Validation pipeline steps 3-6 (auth + JSON shape are handled upstream by the
    # controller and committee). Cheap rejects first; any failure → snapshot not
    # applied at all. Per-user validation is collect-all (one round-trip for the
    # agent to fix every error), per open-decision #1 default.
    class Validate < ApplicationService
      COUNT_DRIFT_THRESHOLD = 0.05
      FUTURE_SKEW = 5.minutes
      ALLOWED_STATUSES = %w[active pending_start suspended].freeze
      EMAIL_RE = URI::MailTo::EMAIL_REGEXP

      def initialize(source:, as_of:, expected_count:, users:, payload_hash:)
        @source = source
        @as_of = as_of
        @expected_count = expected_count
        @users = users
        @payload_hash = payload_hash
      end

      def call
        freshness = check_freshness
        return freshness if freshness

        return failure(:as_of_in_future) if @as_of.nil? || @as_of >= Time.current + FUTURE_SKEW

        count = check_count
        return count if count

        per_user = check_users
        return per_user if per_user

        success
      end

      private

      def check_freshness
        last = SnapshotRun.last_applied_as_of(@source)
        return nil if last.nil? || @as_of.nil?

        if @as_of < last
          failure(:stale_snapshot, last_applied_as_of: last.iso8601)
        elsif @as_of == last
          prior = SnapshotRun.applied.find_by(source: @source, as_of: @as_of)
          if prior&.payload_hash == @payload_hash
            failure(:duplicate_snapshot, snapshot_run_id: prior.id)
          else
            failure(:conflicting_snapshot, last_applied_as_of: last.iso8601)
          end
        end
      end

      def check_count
        size = @users.size
        denom = [ @expected_count.to_i, 1 ].max
        drift = (size - @expected_count.to_i).abs.to_f / denom
        return nil if drift <= COUNT_DRIFT_THRESHOLD
        failure(:count_mismatch, expected_count: @expected_count.to_i, actual_count: size)
      end

      def check_users
        terminated_indices = []
        errors = []

        @users.each_with_index do |u, i|
          terminated_indices << i if u[:status].to_s == "terminated"

          field_errors = user_field_errors(u)
          errors << { "index" => i, "external_id" => u[:external_id], "errors" => field_errors } if field_errors.any?
        end

        return failure(:terminated_in_snapshot, indices: terminated_indices) if terminated_indices.any?
        return failure(:validation_failed, errors: errors) if errors.any?
        nil
      end

      def user_field_errors(u)
        e = {}
        e["external_id"] = "is required" if u[:external_id].blank?
        e["email"] = "is invalid" if u[:email].blank? || !EMAIL_RE.match?(u[:email].to_s)
        e["name"] = "is required" if u[:name].blank?
        if u[:status].present? && !ALLOWED_STATUSES.include?(u[:status].to_s) && u[:status].to_s != "terminated"
          e["status"] = "is not a valid snapshot status"
        end
        e["start_date"] = "is not a valid date" unless valid_date?(u[:start_date])
        e["end_date"] = "is not a valid date" unless valid_date?(u[:end_date])
        e
      end

      def valid_date?(value)
        return true if value.blank?
        Date.iso8601(value.to_s)
        true
      rescue ArgumentError, TypeError
        false
      end
    end
  end
end
