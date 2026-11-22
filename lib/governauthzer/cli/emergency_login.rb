module Governauthzer
  module CLI
    # Issues a single-use, short-TTL login URL for the given user.
    #
    # Generates a 256-bit random token (`SecureRandom.urlsafe_base64(32)`), stores its
    # SHA-256 digest in `emergency_tokens.token_digest` (one-way), and prints a URL
    # carrying the raw token in its fragment. The plain token never persists.
    #
    # Wrapped in one transaction + one `Current.set(correlation_id:)`.
    # Emits `auth.emergency_token.issued` audit event.
    class EmergencyLogin
      def initialize(user_email:, reason:, issued_by_email: nil)
        @user_email      = user_email
        @reason          = reason
        @issued_by_email = issued_by_email
      end

      def run
        Current.set(correlation_id: SecureRandom.uuid) do
          ActiveRecord::Base.transaction do
            user      = resolve_user!
            issued_by = resolve_issued_by!

            raw_token = SecureRandom.urlsafe_base64(32)
            token = ::EmergencyToken.create!(
              user: user,
              issued_by: issued_by,
              token_digest: ::EmergencyToken.digest(raw_token),
              reason: @reason,
              expires_at: Time.current + ::EmergencyToken::TTL
            )

            ::AuditEvent.record!(
              event_type: "auth.emergency_token.issued",
              actor: issued_by || :system,
              targets: [ token, user ],
              justification: @reason,
              metadata: { "source" => "emergency-login-cli" }
            )

            print_url(user: user, token: token, raw_token: raw_token)
          end
        end
      rescue ActiveRecord::RecordInvalid => e
        abort "ERROR: #{e.record.class.name} invalid — #{e.record.errors.full_messages.join('; ')}"
      end

      private

      def resolve_user!
        user = ::User.find_by(email: @user_email)
        abort "ERROR: no user with email #{@user_email}"        if user.nil?
        abort "ERROR: user #{@user_email} is not active (status=#{user.status})" unless user.active?
        user
      end

      def resolve_issued_by!
        return nil if @issued_by_email.nil? || @issued_by_email.empty?
        issuer = ::User.find_by(email: @issued_by_email)
        abort "ERROR: no user with email #{@issued_by_email} (--issued-by)" if issuer.nil?
        issuer
      end

      def print_url(user:, token:, raw_token:)
        # After `#`: browsers never send the fragment, so the token stays out of every
        # access log, proxy log and error report between the browser and the app.
        url = "#{Rails.application.routes.url_helpers.emergency_login_url}##{raw_token}"
        puts <<~OUT
          Issued one-time login URL for #{user.email}.

            #{url}

          Open it and confirm. Without JavaScript, open the URL and paste this token:

            #{raw_token}

          Expires: #{token.expires_at.utc.iso8601} (#{(::EmergencyToken::TTL / 60).to_i} minutes)
          Single use. Don't paste the URL into a chat or email: link previews would open it.
        OUT
      end
    end
  end
end
