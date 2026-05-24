class EmergencyLoginsController < ApplicationController
  def redeem
    token = EmergencyToken.find_by_raw_token(params[:token])

    if token.nil? || !token.redeemable? || !token.user.active?
      Rails.logger.warn(
        "[emergency-login] redemption rejected token_id=#{token&.id || 'missing'} " \
        "ip=#{request.remote_ip}"
      )
      render :invalid, status: :not_found
      return
    end

    ActiveRecord::Base.transaction do
      unless token.claim!
        Rails.logger.warn("[emergency-login] race lost token_id=#{token.id} ip=#{request.remote_ip}")
        render :invalid, status: :not_found
        return
      end

      user = token.user
      sign_in(user)

      AuditEvent.record!(
        event_type: "auth.emergency_login.succeeded",
        actor: user,
        targets: [ token, user ],
        justification: token.reason,
        metadata: { "source" => "emergency-login-redemption" }
      )

      render :redeemed
    end
  end
end
