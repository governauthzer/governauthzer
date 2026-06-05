module Sync
  module Snapshots
    # Performs the writes for a validated, non-dry-run snapshot. Assumes the caller
    # (Sync::Snapshots::Apply) has opened the surrounding transaction.
    #
    # Order: create → update → drop identities → orphan affected users → pass-2
    # manager resolution. Returns success(summary) where summary = { diff:, orphaned:,
    # warnings: }.
    class ApplyDiff < ApplicationService
      include UserAttributes

      def initialize(source:, diff:, actor:)
        @source = source
        @diff = diff
        @actor = actor
        @resolved = {}      # external_id => User (incoming users, for pass-2 manager link)
        @warnings = []
      end

      def call
        created = create_new
        updated = update_existing
        dropped = drop_gone
        orphaned = orphan_affected
        resolve_managers

        summary = {
          diff: {
            "users_created" => created,
            "users_updated" => updated,
            "users_unchanged" => @diff.existing.size - updated,
            "identities_dropped" => dropped,
            "users_orphaned" => orphaned.size,
            "users_terminated" => 0
          },
          orphaned: orphaned,
          warnings: @warnings
        }
        success(summary)
      end

      private

      def create_new
        @diff.new_users.each do |payload|
          user = User.new(assignable_attrs(payload))
          user.external_identities.build(source: @source, external_id: payload[:external_id])
          user.save!
          @resolved[payload[:external_id]] = user
          AuditEvent.record!(
            event_type: "user.created",
            actor: @actor,
            targets: [ user, *user.external_identities ],
            metadata: { "source" => "api", "via" => "snapshot", "hris_source" => @source }
          )
        end
        @diff.new_users.size
      end

      def update_existing
        count = 0
        @diff.existing.each do |entry|
          user = User.find(entry[:user_id])
          user.assign_attributes(assignable_attrs(entry[:payload]))
          changes = user.changes
          user.save!
          @resolved[entry[:payload][:external_id]] = user
          next if changes.empty?

          count += 1
          AuditEvent.record!(
            event_type: "user.updated",
            actor: @actor,
            targets: user,
            attribute_changes: changes,
            metadata: { "source" => "api", "via" => "snapshot", "hris_source" => @source }
          )
        end
        count
      end

      # Drop all gone identities first, so a user with several same-source
      # identities is only evaluated for orphaning after every drop is applied.
      def drop_gone
        @diff.gone.each do |g|
          identity = ExternalIdentity.find(g[:identity_id])
          user = identity.user
          AuditEvent.record!(
            event_type: "external_identity.unlinked",
            actor: @actor,
            targets: [ user, identity ],
            metadata: { "source" => "api", "via" => "snapshot", "hris_source" => @source }
          )
          identity.destroy!
        end
        @diff.gone.size
      end

      def orphan_affected
        @diff.orphan_user_ids.map do |user_id|
          user = User.find(user_id)
          OrphanedCascade.call(user: user, actor: @actor, source: "api", via: "snapshot")
          { "id" => user.id, "email" => user.email }
        end
      end

      # Pass 2 — manager resolution within the batch. Forward references work
      # because every incoming user was upserted in pass 1 above. Snapshot managers
      # are same-source scalars (manager_external_id), so cross-source is N/A here.
      def resolve_managers
        @resolved.each do |external_id, user|
          payload = incoming_payload(external_id)
          next unless payload.key?(:manager_external_id)

          mgr_ext = payload[:manager_external_id]
          if mgr_ext.blank?
            assign_manager(user, nil)
            next
          end

          manager = ExternalIdentity.find_by(source: @source, external_id: mgr_ext)&.user
          if manager.nil?
            @warnings << { "code" => "dangling_manager", "external_id" => external_id, "manager_external_id" => mgr_ext }
          elsif manager.id == user.id
            @warnings << { "code" => "self_manager", "external_id" => external_id }
          else
            assign_manager(user, manager.id)
          end
        end
      end

      def assign_manager(user, manager_id)
        user.manager_id = manager_id
        return unless user.manager_id_changed?

        changes = user.changes
        user.save!
        AuditEvent.record!(
          event_type: "user.updated",
          actor: @actor,
          targets: user,
          attribute_changes: changes,
          metadata: { "source" => "api", "via" => "snapshot", "hris_source" => @source }
        )
      end

      def incoming_payload(external_id)
        @incoming ||= (@diff.new_users + @diff.existing.map { |e| e[:payload] }).index_by { |p| p[:external_id] }
        @incoming.fetch(external_id)
      end
    end
  end
end
