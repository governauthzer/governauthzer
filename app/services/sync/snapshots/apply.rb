module Sync
  module Snapshots
    # Orchestrates the snapshot pipeline: parse → validate → diff → circuit-breaker
    # → (dry-run shortcut) → apply. Source is taken from the token scope, never the
    # body. Atomic-or-nothing: any failure returns before writes, and the apply
    # itself runs in a single transaction.
    class Apply < ApplicationService
      include UserAttributes

      CIRCUIT_BREAKER_THRESHOLD = 0.10

      def initialize(api_token:, params:, actor: :system)
        @api_token = api_token
        @source = api_token.source
        @params = params
        @actor = actor
      end

      def call
        as_of = parse_time(@params[:as_of])
        users = normalize_users(@params[:users])
        payload_hash = compute_payload_hash(users)

        validation = Validate.call(
          source: @source,
          as_of: as_of,
          expected_count: @params[:expected_count],
          users: users,
          payload_hash: payload_hash
        )
        return validation unless validation.success

        diff = Diff.new(source: @source, users: users).compute

        breaker = check_circuit_breaker(diff)
        return breaker if breaker

        return success(preview_summary(diff, as_of)) if truthy?(@params[:dry_run])

        apply!(diff, as_of, payload_hash, users.size)
      end

      private

      def apply!(diff, as_of, payload_hash, user_count)
        result = nil
        ActiveRecord::Base.transaction do
          summary = ApplyDiff.new(source: @source, diff: diff, actor: @actor).call.value

          run = SnapshotRun.create!(
            source: @source,
            as_of: as_of,
            applied_at: Time.current,
            status: "applied",
            payload_hash: payload_hash,
            user_count: user_count,
            diff_summary: summary[:diff],
            warnings: summary[:warnings],
            api_token: @api_token
          )

          AuditEvent.record!(
            event_type: "sync.snapshot.applied",
            actor: @actor,
            targets: run,
            metadata: {
              "source" => "api",
              "via" => "snapshot",
              "hris_source" => @source,
              "as_of" => as_of.iso8601,
              "diff" => summary[:diff],
              "api_token_id" => @api_token.id,
              "api_token_name" => @api_token.name
            }
          )

          result = success(
            source: @source,
            as_of: as_of,
            applied: true,
            diff: summary[:diff],
            orphaned: summary[:orphaned],
            warnings: summary[:warnings],
            snapshot_run_id: run.id
          )
        end
        result
      end

      def check_circuit_breaker(diff)
        orphans = diff.orphan_user_ids.size
        return nil if orphans.zero?

        source_user_count = ExternalIdentity.where(source: @source).count
        return nil if source_user_count.zero?

        ratio = orphans.to_f / source_user_count
        return nil if ratio <= CIRCUIT_BREAKER_THRESHOLD
        return nil if truthy?(@params[:override_circuit_breaker])

        failure(
          :mass_termination_blocked,
          orphans: orphans,
          source_user_count: source_user_count,
          ratio: ratio.round(4),
          threshold: CIRCUIT_BREAKER_THRESHOLD
        )
      end

      def preview_summary(diff, as_of)
        updated = diff.existing.count do |entry|
          user = User.find(entry[:user_id])
          user.assign_attributes(assignable_attrs(entry[:payload]))
          user.changed?
        end

        {
          source: @source,
          as_of: as_of,
          applied: false,
          diff: {
            "users_created" => diff.new_users.size,
            "users_updated" => updated,
            "users_unchanged" => diff.existing.size - updated,
            "identities_dropped" => diff.gone.size,
            "users_orphaned" => diff.orphan_user_ids.size,
            "users_terminated" => 0
          },
          orphaned: diff.orphan_user_ids.map { |id| { "id" => id, "email" => User.find(id).email } },
          warnings: [],
          snapshot_run_id: nil
        }
      end

      def normalize_users(raw)
        Array(raw).map do |u|
          h = u.respond_to?(:to_unsafe_h) ? u.to_unsafe_h : u
          h.symbolize_keys
        end
      end

      def parse_time(value)
        return nil if value.blank?
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def compute_payload_hash(users)
        canonical = users.sort_by { |u| u[:external_id].to_s }
                         .map { |u| u.sort.to_h }
                         .to_json
        Digest::SHA256.hexdigest(canonical)
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end
    end
  end
end
