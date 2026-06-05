class Admin::ApiTokensController < Admin::BaseController
  before_action :find_token, only: :destroy

  def index
    @api_tokens = ApiToken.order(:name)
    @plain_token = flash[:plain_token]
    @plain_token_name = flash[:plain_token_name]
  end

  def new
    @api_token = ApiToken.new
  end

  def create
    raw_token = ApiToken.generate_raw_token
    @api_token = ApiToken.new(
      name:         token_params[:name],
      expires_at:   parse_expires_at(token_params[:expires_at]),
      source:       token_params[:source],
      token_digest: ApiToken.digest(raw_token)
    )
    if @api_token.save
      AuditEvent.record!(
        event_type: "api_token.created",
        actor: current_user,
        targets: @api_token,
        metadata: { "source" => "admin-ui" }
      )
      flash[:plain_token] = raw_token
      flash[:plain_token_name] = @api_token.name
      redirect_to admin_api_tokens_path, notice: "Token created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    snapshot = { "id" => @api_token.id, "name" => @api_token.name }
    @api_token.destroy!
    AuditEvent.record!(
      event_type: "api_token.deleted",
      actor: current_user,
      targets: @api_token,
      metadata: { "source" => "admin-ui", "snapshot" => snapshot }
    )
    redirect_to admin_api_tokens_path, notice: "Token revoked."
  end

  private

  def find_token
    @api_token = ApiToken.find(params[:id])
  end

  def token_params
    params.require(:api_token).permit(:name, :expires_at, :source)
  end

  def parse_expires_at(raw)
    return nil if raw.blank?
    Time.zone.parse(raw)
  rescue ArgumentError
    nil
  end
end
