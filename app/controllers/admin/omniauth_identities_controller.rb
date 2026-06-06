class Admin::OmniauthIdentitiesController < Admin::BaseController
  before_action :find_user, only: :create
  before_action :find_identity, only: :destroy

  # Operator-driven OIDC subject linking (STRICT login has no auto-link). The
  # operator copies the subject claim from their IdP console and pastes it here.
  def create
    identity = @user.omniauth_identities.new(identity_params)
    if identity.save
      record_admin_audit("omniauth_identity.linked", identity)
      redirect_to admin_user_path(@user), notice: "Identity linked."
    else
      redirect_to admin_user_path(@user), alert: "Cannot link: #{identity.errors.full_messages.join('; ')}"
    end
  end

  def destroy
    user = @identity.user
    snapshot = {
      "id" => @identity.id, "auth_provider_id" => @identity.auth_provider_id, "subject" => @identity.subject
    }
    @identity.destroy
    record_admin_audit("omniauth_identity.unlinked", @identity, snapshot: snapshot)
    redirect_to admin_user_path(user), notice: "Identity unlinked."
  end

  private

  def find_user
    @user = User.find(params[:user_id])
  end

  def find_identity
    @identity = OmniauthIdentity.find(params[:id])
  end

  def identity_params
    params.require(:omniauth_identity).permit(:auth_provider_id, :subject)
  end
end
