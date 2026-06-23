require "test_helper"

class AuthProviderTest < ActiveSupport::TestCase
  def valid_attrs(**overrides)
    {
      name: "Keycloak",
      slug: "keycloak",
      oidc_issuer_url: "https://idp.example.com/realms/main",
      oidc_client_id: "governauthzer",
      oidc_scope: "openid email profile",
      claim_mappings: []
    }.merge(overrides)
  end

  test "valid with the required attributes" do
    assert AuthProvider.new(valid_attrs).valid?
  end

  test "requires name, slug, issuer and client_id" do
    provider = AuthProvider.new
    assert_not provider.valid?
    %i[name slug oidc_issuer_url oidc_client_id].each do |attr|
      assert provider.errors[attr].any?, "expected a presence error on #{attr}"
    end
  end

  test "requires oidc_scope (which has a DB default, so blank it explicitly)" do
    provider = AuthProvider.new(valid_attrs(oidc_scope: ""))
    assert_not provider.valid?
    assert provider.errors[:oidc_scope].any?
  end

  test "slug uniqueness" do
    AuthProvider.create!(valid_attrs)
    dup = AuthProvider.new(valid_attrs(name: "Other"))
    assert_not dup.valid?
    assert dup.errors[:slug].any?
  end

  test "normalizes the slug (lowercase, non-alnum to dash, squeezed)" do
    provider = AuthProvider.create!(valid_attrs(slug: "Keycloak  Prod!!"))
    assert_equal "keycloak-prod-", provider.slug
  end

  test "enabled scope returns only enabled providers" do
    on = AuthProvider.create!(valid_attrs(slug: "on", enabled: true))
    AuthProvider.create!(valid_attrs(slug: "off", enabled: false))
    assert_includes AuthProvider.enabled, on
    assert_equal [ on ], AuthProvider.enabled.where(slug: %w[on off]).to_a
  end

  test "oidc_client_secret is encrypted at rest" do
    provider = AuthProvider.create!(valid_attrs(oidc_client_secret: "s3cr3t-value"))
    assert_equal "s3cr3t-value", provider.reload.oidc_client_secret, "decrypts on read"
    assert_not_equal "s3cr3t-value", provider.ciphertext_for(:oidc_client_secret), "stored ciphertext differs from plaintext"
  end

  test "discovery_endpoint is computed from the issuer, trimming a trailing slash" do
    provider = AuthProvider.new(valid_attrs(oidc_issuer_url: "https://idp.example.com/realms/main/"))
    assert_equal "https://idp.example.com/realms/main/.well-known/openid-configuration", provider.discovery_endpoint
  end

  test "discovery_endpoint is nil without an issuer" do
    assert_nil AuthProvider.new(oidc_issuer_url: "").discovery_endpoint
  end

  test "claim_mappings= parses a JSON array string" do
    provider = AuthProvider.new(valid_attrs(claim_mappings: '[{"claim":"groups","equals":"admins","role":"x"}]'))
    assert provider.valid?
    assert_equal [ { "claim" => "groups", "equals" => "admins", "role" => "x" } ], provider.claim_mappings
  end

  test "claim_mappings= treats a blank string as an empty array" do
    provider = AuthProvider.new(valid_attrs(claim_mappings: "   "))
    assert provider.valid?
    assert_equal [], provider.claim_mappings
  end

  test "claim_mappings= records a validation error on invalid JSON and keeps the raw input" do
    provider = AuthProvider.new(valid_attrs(claim_mappings: "{ not json"))
    assert_not provider.valid?
    assert_match(/not valid JSON/, provider.errors[:claim_mappings].join)
    assert_equal "{ not json", provider.claim_mappings_raw
  end

  test "claim_mappings= rejects valid JSON that is not an array" do
    provider = AuthProvider.new(valid_attrs(claim_mappings: '{"claim":"groups"}'))
    assert_not provider.valid?
    assert_match(/must be a JSON array/, provider.errors[:claim_mappings].join)
  end

  test "deleting a provider with linked identities is blocked" do
    provider = AuthProvider.create!(valid_attrs)
    user = User.create!(email: "id@example.com", name: "Id")
    provider.omniauth_identities.create!(user: user, subject: "sub-123")

    assert_not provider.destroy
    assert AuthProvider.exists?(provider.id)
    assert provider.errors[:base].any?
  end
end
