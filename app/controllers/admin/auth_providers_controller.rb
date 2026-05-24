class Admin::AuthProvidersController < Admin::BaseController
  before_action :find_auth_provider, only: %i[edit update destroy]

  def index
    @auth_providers = AuthProvider.order(:name)
  end

  def new
    @auth_provider = AuthProvider.new(oidc_scope: "openid email profile", claim_mappings: [])
  end

  def create
    @auth_provider = AuthProvider.new(create_attrs)
    if @auth_provider.save
      AuditEvent.record!(
        event_type: "auth_provider.created",
        actor: current_user,
        targets: @auth_provider,
        metadata: { "source" => "admin-ui" }
      )
      redirect_to admin_auth_providers_path, notice: "Provider created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @auth_provider.assign_attributes(update_attrs)
    changed = @auth_provider.changes
    if @auth_provider.save
      AuditEvent.record!(
        event_type: "auth_provider.updated",
        actor: current_user,
        targets: @auth_provider,
        attribute_changes: redact_secret_diff(changed),
        metadata: { "source" => "admin-ui" }
      )
      redirect_to admin_auth_providers_path, notice: "Provider updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    snapshot = { "id" => @auth_provider.id, "slug" => @auth_provider.slug, "name" => @auth_provider.name }
    if @auth_provider.destroy
      AuditEvent.record!(
        event_type: "auth_provider.deleted",
        actor: current_user,
        targets: @auth_provider,
        metadata: { "source" => "admin-ui", "snapshot" => snapshot }
      )
      redirect_to admin_auth_providers_path, notice: "Provider deleted."
    else
      redirect_to admin_auth_providers_path,
                  alert: "Cannot delete: #{@auth_provider.errors.full_messages.join('; ')}"
    end
  end

  private

  def find_auth_provider
    @auth_provider = AuthProvider.find(params[:id])
  end

  def create_attrs
    permitted_params
  end

  def update_attrs
    attrs = permitted_params
    # If operator left the secret field blank on edit, don't overwrite the stored secret.
    attrs.delete(:oidc_client_secret) if attrs[:oidc_client_secret].blank?
    attrs
  end

  def permitted_params
    params.require(:auth_provider).permit(
      :name, :slug, :enabled, :oidc_issuer_url, :oidc_client_id, :oidc_client_secret,
      :oidc_scope, :claim_mappings
    )
  end

  def redact_secret_diff(changes)
    return changes unless changes.key?("oidc_client_secret")
    changes.merge("oidc_client_secret" => [ "[REDACTED]", "[REDACTED]" ])
  end
end
