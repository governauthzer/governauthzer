class Admin::WebhookSubscriptionsController < Admin::BaseController
  before_action :find_subscription, only: %i[show edit update destroy rotate_secret]
  before_action :load_form_applications, only: %i[new create edit update]

  def index
    @subscriptions = WebhookSubscription.order(:name)
  end

  def show
    @recent_deliveries = @subscription.webhook_deliveries.order(created_at: :desc).limit(20)
  end

  def new
    @subscription = WebhookSubscription.new
  end

  def create
    @subscription = WebhookSubscription.new(subscription_params)
    if @subscription.save
      record_admin_audit("webhook_subscription.created", @subscription)
      redirect_to admin_webhook_subscription_path(@subscription), notice: "Webhook subscription created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @subscription.assign_attributes(subscription_params)
    changes = @subscription.changes
    if @subscription.save
      record_admin_audit("webhook_subscription.updated", @subscription, attribute_changes: changes)
      redirect_to admin_webhook_subscription_path(@subscription), notice: "Webhook subscription updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # The signing secret is a shared HMAC key (stored plaintext, like a Stripe webhook
  # secret) — rotating it requires updating the provisioner's config to match.
  def rotate_secret
    @subscription.update!(signing_secret: SecureRandom.hex(32))
    record_admin_audit("webhook_subscription.secret_rotated", @subscription)
    redirect_to admin_webhook_subscription_path(@subscription),
                notice: "Signing secret rotated — update your provisioner config."
  end

  def destroy
    snapshot = { "id" => @subscription.id, "name" => @subscription.name, "endpoint_url" => @subscription.endpoint_url }
    @subscription.destroy
    record_admin_audit("webhook_subscription.deleted", @subscription, snapshot: snapshot)
    redirect_to admin_webhook_subscriptions_path, notice: "Webhook subscription deleted."
  end

  private

  def find_subscription
    @subscription = WebhookSubscription.find(params[:id])
  end

  # Provisionable applications for the filter checkboxes (the self/operator app is
  # never provisioned outbound, so it's not selectable).
  def load_form_applications
    @form_applications = Application.where.not(slug: Application::SELF_SLUG).order(:name)
  end

  def subscription_params
    permitted = params.require(:webhook_subscription)
                      .permit(:name, :endpoint_url, :active, event_types: [], application_ids: [])
    # Unchecked checkbox groups submit no key — coerce to [] so "clear all" works
    # and an empty filter means "all" (the wildcard).
    permitted[:event_types] ||= []
    permitted[:application_ids] ||= []
    permitted
  end
end
