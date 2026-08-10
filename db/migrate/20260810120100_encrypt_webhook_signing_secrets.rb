class EncryptWebhookSigningSecrets < ActiveRecord::Migration[8.1]
  # Local model, not WebhookSubscription: a data migration has to keep meaning what
  # it meant on the day it ran, whatever the real model grows into later.
  class Subscription < ActiveRecord::Base
    self.table_name = "webhook_subscriptions"
    encrypts :signing_secret
  end

  # Existing installs hold their signing secrets in plaintext. Reading one through
  # an encrypted attribute is an error unless unencrypted data is tolerated, so the
  # tolerance is switched on for the length of the backfill and no longer — leaving
  # it on permanently would mean a row that was never encrypted keeps working
  # silently, which is exactly the state this migration exists to end.
  def up
    with_unencrypted_data_supported { Subscription.find_each(&:encrypt) }
  end

  def down
    with_unencrypted_data_supported { Subscription.find_each(&:decrypt) }
  end

  private

  def with_unencrypted_data_supported
    config = ActiveRecord::Encryption.config
    previous = config.support_unencrypted_data
    config.support_unencrypted_data = true
    yield
  ensure
    config.support_unencrypted_data = previous
  end
end
