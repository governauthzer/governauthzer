module Users
  class Updater < ApplicationService
    include Users::ManagerReferenceResolver

    def initialize(user:, attrs:, actor:, manager_external_id: NOT_PROVIDED)
      @user = user
      @attrs = attrs
      @actor = actor
      @manager_external_id = manager_external_id
    end

    def call
      return failure(:reactivation_required, user_id: @user.id) if @user.terminated?

      ActiveRecord::Base.transaction do
        resolved_attrs, manager_failure = resolve_manager_reference(@attrs, @manager_external_id)
        return manager_failure if manager_failure

        @user.assign_attributes(resolved_attrs)
        attribute_changes = @user.changes
        @user.save!

        if attribute_changes.any?
          AuditEvent.record!(
            event_type: "user.updated",
            actor: @actor,
            targets: @user,
            attribute_changes: attribute_changes,
            metadata: { "source" => "api" }
          )
        end

        success(@user)
      end
    end
  end
end
