# Audit-log tamper protection (see db/grants.sql). In production the app should
# connect as a restricted role that can INSERT/SELECT audit_events but not
# UPDATE/DELETE it, so `rails console` can't silently rewrite or erase history. If the
# app connected as a privileged role (UPDATE allowed), the protection is NOT in effect
# — warn loudly so it's visible in the boot logs. Warn, not fail-fast: single-role
# operation is a legitimate default (evaluation, simple installs); the operator just
# shouldn't believe they're protected when they aren't. (Real DBA/superuser-level
# tamper-evidence is external append-only log shipping, a separate deferred concern.)
if Rails.env.production?
  Rails.application.config.after_initialize do
    begin
      can_update = ActiveModel::Type::Boolean.new.cast(
        ActiveRecord::Base.connection.select_value(
          "SELECT has_table_privilege(current_user, 'audit_events', 'UPDATE')"
        )
      )
      if can_update
        Rails.logger.warn(
          "[security] The app's database role can UPDATE audit_events — audit-log " \
          "tamper protection is NOT in effect. Apply db/grants.sql as the owner role and " \
          "serve as the restricted role (GOVERNAUTHZER_DATABASE_USER=governauthzer_app)."
        )
      end
    rescue => e
      # DB may be unreachable at boot (asset precompile, migrations not yet run) — never
      # let the check itself break boot.
      Rails.logger.warn("[security] Could not verify audit-log protection: #{e.class}: #{e.message}")
    end
  end
end
