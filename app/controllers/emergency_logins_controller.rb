# Break-glass sign-in with a single-use token issued from the server shell
# (`bin/governauthzer emergency-login`).
#
# The token never travels in a URL path. The CLI prints `/emergency-login#<token>`:
# the fragment is not sent to the server, so it reaches no access log, proxy log or
# error report. The confirm page (GET) reads it in the browser and the operator's click
# POSTs it, where `:token` is a filtered parameter. Redemption needs that click on
# purpose: link previews and mail scanners — some of which run JavaScript — fetch a
# URL but don't press buttons, so they can neither burn the token nor be handed the
# session.
class EmergencyLoginsController < ApplicationController
  def show
  end

  def create
    token = EmergencyToken.find_by_raw_token(submitted_token)

    if token.nil? || !token.redeemable? || !token.user.active?
      Rails.logger.warn(
        "[emergency-login] redemption rejected token_id=#{token&.id || 'missing'} ip=#{request.remote_ip}"
      )
      return render(:invalid, status: :not_found)
    end

    # Only the writes are transactional; rendering happens after the block.
    redeemed = ActiveRecord::Base.transaction do
      next false unless token.claim!

      AuditEvent.record!(
        event_type: "auth.emergency_login.succeeded",
        actor: token.user,
        targets: [ token, token.user ],
        justification: token.reason,
        metadata: { "source" => "emergency-login-redemption" }
      )
      true
    end

    unless redeemed
      Rails.logger.warn("[emergency-login] race lost token_id=#{token.id} ip=#{request.remote_ip}")
      return render(:invalid, status: :not_found)
    end

    sign_in(token.user)
    redirect_to root_path, notice: "Signed in as #{token.user.name} with an emergency login."
  end

  private

  # Accepts the bare token, or a whole pasted URL — whatever follows its last `#`.
  def submitted_token
    params[:token].to_s.split("#").last.to_s.strip
  end
end
