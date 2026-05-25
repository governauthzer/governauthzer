module Users
  class Creator < ApplicationService
    def initialize(attrs:, external_identities: [], omniauth_identities: [], actor:)
      @attrs = attrs
      @external_identities = external_identities
      @omniauth_identities = omniauth_identities
      @actor = actor
    end

    def call
      ActiveRecord::Base.transaction do
        collision = check_external_collisions
        return collision if collision

        collision = check_omniauth_collisions
        return collision if collision

        user = User.new(@attrs)

        @external_identities.each do |ei|
          user.external_identities.build(source: ei[:source], external_id: ei[:external_id])
        end

        @omniauth_identities.each do |oi|
          provider = AuthProvider.find_by(slug: oi[:auth_provider_slug])
          return failure(:unknown_auth_provider_slug, slug: oi[:auth_provider_slug]) unless provider
          user.omniauth_identities.build(auth_provider: provider, subject: oi[:subject])
        end

        user.save!

        AuditEvent.record!(
          event_type: "user.created",
          actor: @actor,
          targets: [ user, *user.external_identities, *user.omniauth_identities ],
          metadata: { "source" => "api" }
        )

        success(user)
      end
    end

    private

    def check_external_collisions
      @external_identities.each do |ei|
        normalized = ExternalIdentity.normalize_source(ei[:source])
        existing = ExternalIdentity.find_by(source: normalized, external_id: ei[:external_id])
        next unless existing

        return failure(
          :external_id_collision,
          existing_user_id: existing.user_id,
          source: ei[:source],
          external_id: ei[:external_id]
        )
      end
      nil
    end

    def check_omniauth_collisions
      @omniauth_identities.each do |oi|
        provider = AuthProvider.find_by(slug: oi[:auth_provider_slug])
        next unless provider
        existing = OmniauthIdentity.find_by(auth_provider: provider, subject: oi[:subject])
        next unless existing

        return failure(
          :omniauth_identity_collision,
          existing_user_id: existing.user_id,
          auth_provider_slug: oi[:auth_provider_slug],
          subject: oi[:subject]
        )
      end
      nil
    end
  end
end
