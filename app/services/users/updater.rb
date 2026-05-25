module Users
  class Updater < ApplicationService
    def initialize(user:, attrs:, actor:)
      @user = user
      @attrs = attrs
      @actor = actor
    end

    def call
      return failure(:reactivation_required, user_id: @user.id) if @user.terminated?

      ActiveRecord::Base.transaction do
        @user.assign_attributes(@attrs)
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
