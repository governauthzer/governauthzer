module Sync
  module Snapshots
    # Pure read-only diff of an incoming snapshot against the current DB state for
    # one source. No writes — safe for circuit-breaker preview and dry-run.
    #
    # Key = external_id (unique within a source). Three buckets via set ops:
    #   new      = incoming − db   (create user + identity)
    #   existing = incoming ∩ db   (update attrs if changed)
    #   gone     = db − incoming   (drop identity, maybe orphan)
    class Diff
      Result = Data.define(:new_users, :existing, :gone, :orphan_user_ids)

      # new_users:  [payload, …]                         (symbol-keyed hashes)
      # existing:   [{ payload:, user_id: }, …]
      # gone:       [{ external_id:, user_id:, identity_id: }, …]
      # orphan_user_ids: Set of user_ids left with zero identities after the drop

      def initialize(source:, users:)
        @source = source
        @users = users
      end

      def compute
        incoming = @users.index_by { |u| u[:external_id] }
        db_by_key = ExternalIdentity.where(source: @source)
                                    .select(:id, :external_id, :user_id)
                                    .index_by(&:external_id)

        incoming_keys = incoming.keys.to_set
        db_keys = db_by_key.keys.to_set

        new_users = (incoming_keys - db_keys).map { |k| incoming[k] }
        existing = (incoming_keys & db_keys).map { |k| { payload: incoming[k], user_id: db_by_key[k].user_id } }
        gone = (db_keys - incoming_keys).map do |k|
          { external_id: k, user_id: db_by_key[k].user_id, identity_id: db_by_key[k].id }
        end

        Result.new(new_users:, existing:, gone:, orphan_user_ids: compute_orphans(gone))
      end

      private

      # A user orphans only if ALL of its external_identities are in the gone set
      # (i.e., it has no identity from any other source surviving the drop).
      def compute_orphans(gone)
        gone.group_by { |g| g[:user_id] }.filter_map do |user_id, drops|
          user_id if ExternalIdentity.where(user_id: user_id).count == drops.size
        end.to_set
      end
    end
  end
end
