require "test_helper"

class AdminAuthProvidersTest < ActionDispatch::IntegrationTest
  def setup
    @self_app = Application.create!(name: "Governauthzer", slug: Application::SELF_SLUG)
    operator_role = @self_app.roles.create!(name: "Operator", slug: "operator", protected: true)
    @operator = User.create!(email: "authop@example.com", name: "Auth Op")
    Access.create!(user: @operator, role: operator_role, status: "approved", source: "manual")
    sign_in_as @operator
  end

  def provider_params(**overrides)
    {
      name: "Keycloak",
      slug: "keycloak",
      enabled: "1",
      oidc_issuer_url: "https://idp.example.com/realms/main",
      oidc_client_id: "governauthzer",
      oidc_client_secret: "initial-secret",
      oidc_scope: "openid email profile",
      claim_mappings: "[]"
    }.merge(overrides)
  end

  test "index and new render" do
    AuthProvider.create!(name: "Existing", slug: "existing", oidc_issuer_url: "https://i",
                         oidc_client_id: "c", oidc_scope: "openid", claim_mappings: [])
    get "/admin/auth_providers"
    assert_response :ok
    assert_includes response.body, "Existing"

    get "/admin/auth_providers/new"
    assert_response :ok
  end

  test "operator creates a provider, normalizing the slug and emitting an audit event" do
    assert_difference([ "AuthProvider.count", "AuditEvent.where(event_type: 'auth_provider.created').count" ], 1) do
      post "/admin/auth_providers", params: { auth_provider: provider_params(slug: "Key Cloak") }
    end
    assert_redirected_to "/admin/auth_providers"
    assert_equal "key-cloak", AuthProvider.find_by(name: "Keycloak").slug
  end

  test "invalid claim_mappings JSON re-renders the form unprocessable without creating" do
    assert_no_difference("AuthProvider.count") do
      post "/admin/auth_providers", params: { auth_provider: provider_params(claim_mappings: "{ broken") }
    end
    assert_response :unprocessable_content
  end

  test "blank secret on edit keeps the stored secret; a provided secret rotates it" do
    provider = AuthProvider.create!(name: "Keycloak", slug: "keycloak", oidc_issuer_url: "https://i",
                                    oidc_client_id: "c", oidc_scope: "openid",
                                    oidc_client_secret: "stored-secret", claim_mappings: [])

    patch "/admin/auth_providers/#{provider.id}",
          params: { auth_provider: provider_params(name: "Keycloak Renamed", oidc_client_secret: "") }
    assert_redirected_to "/admin/auth_providers"
    assert_equal "Keycloak Renamed", provider.reload.name
    assert_equal "stored-secret", provider.oidc_client_secret, "blank secret preserved the stored value"

    patch "/admin/auth_providers/#{provider.id}",
          params: { auth_provider: provider_params(oidc_client_secret: "rotated-secret") }
    assert_equal "rotated-secret", provider.reload.oidc_client_secret
  end

  test "the audit diff redacts the secret instead of storing it" do
    provider = AuthProvider.create!(name: "Keycloak", slug: "keycloak", oidc_issuer_url: "https://i",
                                    oidc_client_id: "c", oidc_scope: "openid",
                                    oidc_client_secret: "old-secret", claim_mappings: [])

    patch "/admin/auth_providers/#{provider.id}",
          params: { auth_provider: provider_params(oidc_client_secret: "new-secret") }

    event = AuditEvent.where(event_type: "auth_provider.updated").last
    assert_equal [ "[REDACTED]", "[REDACTED]" ], event.attribute_changes["oidc_client_secret"]
    assert_not_includes event.attribute_changes.to_json, "new-secret"
  end

  test "operator deletes a provider and an audit event is emitted" do
    provider = AuthProvider.create!(name: "Keycloak", slug: "keycloak", oidc_issuer_url: "https://i",
                                    oidc_client_id: "c", oidc_scope: "openid", claim_mappings: [])
    assert_difference("AuthProvider.count", -1) do
      assert_difference("AuditEvent.where(event_type: 'auth_provider.deleted').count", 1) do
        delete "/admin/auth_providers/#{provider.id}"
      end
    end
    assert_redirected_to "/admin/auth_providers"
  end

  test "deleting a provider with linked identities is blocked with an alert" do
    provider = AuthProvider.create!(name: "Keycloak", slug: "keycloak", oidc_issuer_url: "https://i",
                                    oidc_client_id: "c", oidc_scope: "openid", claim_mappings: [])
    user = User.create!(email: "linked@example.com", name: "Linked")
    provider.omniauth_identities.create!(user: user, subject: "sub-1")

    assert_no_difference("AuthProvider.count") do
      delete "/admin/auth_providers/#{provider.id}"
    end
    assert_redirected_to "/admin/auth_providers"
    assert_match(/cannot delete/i, flash[:alert])
  end

  test "a non-operator is forbidden" do
    plain = User.create!(email: "plain-auth@example.com", name: "Plain")
    sign_in_as plain
    get "/admin/auth_providers"
    assert_response :forbidden
  end

  private

  def sign_in_as(user)
    raw = SecureRandom.urlsafe_base64(32)
    EmergencyToken.create!(user: user, token_digest: EmergencyToken.digest(raw),
                           reason: "test sign-in", expires_at: 5.minutes.from_now)
    get "/emergency-login/#{raw}"
  end
end
