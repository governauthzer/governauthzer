# TLS enforcement is default-secure in production (config.force_ssl, see
# config/environments/production.rb). Disabling it (FORCE_SSL=false) is only safe when
# TLS is terminated AND enforced entirely by upstream infrastructure; if it's off by
# mistake, Bearer API tokens and session cookies travel in cleartext. Warn loudly so
# the choice is visible in the boot logs rather than silent.
if Rails.env.production? && !Rails.application.config.force_ssl
  Rails.application.config.after_initialize do
    Rails.logger.warn(
      "[security] config.force_ssl is DISABLED (FORCE_SSL=false). Ensure TLS is " \
      "enforced upstream — Bearer tokens and session cookies over plain HTTP are insecure."
    )
  end
end
