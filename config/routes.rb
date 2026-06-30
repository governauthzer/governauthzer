Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get    "/emergency-login/:token" => "emergency_logins#redeem", as: :emergency_login
  delete "/logout"                 => "sessions#destroy",        as: :logout

  get  "/login"                  => "logins#show",                 as: :login

  # Public API documentation (Redoc). The OpenAPI contract is public by design.
  get  "/api-docs"               => "docs#show", as: :api_docs
  get  "/api-docs/v1.yaml"       => "docs#spec", as: :api_docs_spec
  get  "/auth/:slug/callback"    => "omniauth_sessions#callback",  as: :oidc_callback, constraints: { slug: /[a-z0-9-]+/ }
  get  "/auth/failure"           => "omniauth_sessions#failure",   as: :oidc_failure

  namespace :admin do
    resources :applications do
      resources :roles, only: %i[new create edit update destroy], shallow: true
    end
    resources :approval_workflows do
      resources :approval_steps, only: %i[new create edit update destroy], shallow: true
    end
    resources :users, only: %i[index show update] do
      resources :omniauth_identities, only: :create
    end
    resources :omniauth_identities, only: :destroy
    resources :accesses, only: :destroy
    resources :audit_events, only: %i[index show]
    resources :auth_providers, except: :show
    resources :api_tokens, only: %i[index new create destroy]
    resources :webhook_subscriptions do
      member { post :rotate_secret }
    end
    root to: "dashboard#index"
  end

  namespace :api do
    namespace :v1 do
      get "whoami" => "whoami#show", as: :whoami
      resources :users, only: %i[index show create update destroy]
      patch "users/by-external-id/:source/:external_id" => "users_by_external_id#update",
            as: :user_by_external_id,
            constraints: { external_id: %r{[^/]+} }
      post "sync/snapshots" => "sync/snapshots#create", as: :sync_snapshots
      post "applications/:application_id/reconciliations" => "reconciliations#create",
           as: :application_reconciliations
      get "grants" => "grants#index", as: :grants
    end
  end

  # End-user UI (every signed-in active user; operators land here too) — the
  # self-service request / approval flow. Operator-only screens live under /admin.
  root "dashboard#index"
  get  "/catalog" => "catalog#index", as: :catalog
  resources :access_requests, only: %i[create destroy]
  post "/approvals/:id/approve" => "approvals#approve", as: :approve_access
  post "/approvals/:id/deny"    => "approvals#deny",    as: :deny_access

  # Development-only one-click sign-in. Declared only in development, so these
  # routes simply do not exist in production (404), independent of the controller
  # guard. See Dev::SessionsController.
  if Rails.env.development?
    get  "/dev/sign-in" => "dev/sessions#new",    as: :dev_sign_in
    post "/dev/sign-in" => "dev/sessions#create"

    # Browse captured outgoing mail.
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end
end
