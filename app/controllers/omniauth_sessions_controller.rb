class OmniauthSessionsController < ApplicationController
  def callback
    auth = request.env["omniauth.auth"]
    if auth.nil?
      Rails.logger.warn("[oidc] callback hit without omniauth.auth (slug=#{params[:slug]})")
      redirect_to login_path, alert: "Sign-in failed." and return
    end

    slug = params[:slug]
    provider = AuthProvider.enabled.find_by(slug: slug)
    unless provider
      Rails.logger.warn("[oidc] callback for missing/disabled provider slug=#{slug}")
      redirect_to login_path, alert: "Provider not available." and return
    end

    @subject = auth["uid"]
    identity = OmniauthIdentity.find_by(auth_provider: provider, subject: @subject)

    if identity.nil?
      Rails.logger.warn("[oidc] STRICT miss provider=#{slug} subject=#{@subject}")
      @provider_name = provider.name
      @provider_slug = provider.slug
      render :unregistered, status: :forbidden and return
    end

    user = identity.user
    unless user.active?
      Rails.logger.warn("[oidc] inactive user attempted login user_id=#{user.id} status=#{user.status}")
      @provider_name = provider.name
      @provider_slug = provider.slug
      render :unregistered, status: :forbidden and return
    end

    ActiveRecord::Base.transaction do
      sign_in(user)
      AuditEvent.record!(
        event_type: "auth.login.succeeded",
        actor: user,
        targets: [ identity, user ],
        metadata: { "source" => "oidc", "provider_slug" => slug }
      )
    end

    redirect_to admin_root_path, notice: "Signed in as #{user.name}."
  end

  def failure
    message = params[:message].to_s
    Rails.logger.warn("[oidc] auth failure: #{message} strategy=#{params[:strategy]}")
    redirect_to login_path, alert: "Sign-in failed: #{message.presence || 'unknown error'}"
  end
end
