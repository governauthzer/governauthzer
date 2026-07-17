# Encryption key sourcing strategy:
#
# - Production: keys MUST come from ENV. No fallback to credentials.
#   Boot fails fast if any of the three keys is missing.
# - Development: ENV overrides if set; otherwise falls back to Rails credentials
#   (Rails default behavior at the conventional `active_record_encryption.*` key path).
# - Test: stable hardcoded keys in config/environments/test.rb.
#
# Generate keys for production deployment via `bin/governauthzer generate-encryption-keys`.

unless Rails.env.test?
  if (key = ENV["GOVERNAUTHZER_ENCRYPTION_PRIMARY_KEY"]).present?
    Rails.application.config.active_record.encryption.primary_key = key
  end

  if (key = ENV["GOVERNAUTHZER_ENCRYPTION_DETERMINISTIC_KEY"]).present?
    Rails.application.config.active_record.encryption.deterministic_key = key
  end

  if (salt = ENV["GOVERNAUTHZER_ENCRYPTION_KEY_DERIVATION_SALT"]).present?
    Rails.application.config.active_record.encryption.key_derivation_salt = salt
  end
end

if Rails.env.production?
  Rails.application.config.after_initialize do
    # SECRET_KEY_BASE_DUMMY is Rails' own "booting without real secrets" signal — set
    # only for assets:precompile during image build (Dockerfile), where secrets must
    # not exist. Real server boots never set it, so the fail-fast still guards them.
    next if ENV["SECRET_KEY_BASE_DUMMY"].present?

    encryption = Rails.application.config.active_record.encryption
    missing = []
    missing << "GOVERNAUTHZER_ENCRYPTION_PRIMARY_KEY"         if encryption.primary_key.blank?
    missing << "GOVERNAUTHZER_ENCRYPTION_DETERMINISTIC_KEY"   if encryption.deterministic_key.blank?
    missing << "GOVERNAUTHZER_ENCRYPTION_KEY_DERIVATION_SALT" if encryption.key_derivation_salt.blank?

    if missing.any?
      raise <<~MSG
        Encryption keys missing. Set these ENV vars before booting in production:
          #{missing.join("\n  ")}
        Generate fresh keys with: bin/governauthzer generate-encryption-keys
      MSG
    end
  end
end
