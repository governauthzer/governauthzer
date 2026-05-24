module Governauthzer
  module CLI
    # Creates the first operator user.
    #
    # Idempotent for the governauthzer-itself Application and the operator Role:
    # both are find-or-created. The User itself is *not* idempotent — re-running
    # with the same email returns an error (UNIQUE constraint).
    #
    # All writes wrapped in a transaction and a single correlation_id so the
    # bootstrap operation appears as one logical event in the audit log.
    class SeedAdmin
      OPERATOR_ROLE_SLUG = "operator"
      OPERATOR_ROLE_NAME = "Operator"
      SELF_APP_NAME      = "Governauthzer"

      def initialize(email:, name:)
        @email = email
        @name  = name
      end

      def run
        Current.set(correlation_id: SecureRandom.uuid) do
          ActiveRecord::Base.transaction do
            app    = find_or_create_self_application
            role   = find_or_create_operator_role(app)
            user   = create_user!
            access = grant_operator_access!(user, role)

            emit_audit_events(user: user, access: access)
            print_success(user)
          end
        end
      rescue ActiveRecord::RecordInvalid => e
        abort "ERROR: #{e.record.class.name} invalid — #{e.record.errors.full_messages.join('; ')}"
      rescue ActiveRecord::RecordNotUnique
        abort "ERROR: a user with email #{@email} already exists (and is not terminated). " \
              "Use the admin UI or shell to manage existing operators."
      end

      private

      def find_or_create_self_application
        ::Application.find_or_create_by!(slug: ::Application::SELF_SLUG) do |a|
          a.name = SELF_APP_NAME
        end
      end

      def find_or_create_operator_role(app)
        app.roles.find_or_create_by!(slug: OPERATOR_ROLE_SLUG) do |r|
          r.name = OPERATOR_ROLE_NAME
          r.protected = true
        end
      end

      def create_user!
        ::User.create!(email: @email, name: @name, status: "active")
      end

      def grant_operator_access!(user, role)
        ::Access.create!(
          user: user,
          role: role,
          status: "approved",
          source: "manual",
          requested_by: nil,
          justification: "Bootstrap: seeded by bin/governauthzer seed-admin"
        )
      end

      def emit_audit_events(user:, access:)
        ::AuditEvent.record!(
          event_type: "user.created",
          actor: :system,
          targets: user,
          metadata: { "source" => "seed-admin-cli" }
        )
        ::AuditEvent.record!(
          event_type: "access.approved",
          actor: :system,
          targets: [ access, user, access.role ],
          justification: access.justification,
          metadata: { "source" => "seed-admin-cli", "decision_method" => "bootstrap" }
        )
      end

      def print_success(user)
        puts <<~OUT
          Operator user created.

            id:    #{user.id}
            email: #{user.email}
            name:  #{user.name}

          Next step: issue a one-time login URL for the new operator with
            bin/governauthzer emergency-login --user=#{user.email} --reason="bootstrap"
        OUT
      end
    end
  end
end
