Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get    "/emergency-login/:token" => "emergency_logins#redeem", as: :emergency_login
  delete "/logout"                 => "sessions#destroy",        as: :logout

  get  "/login"                  => "logins#show",                 as: :login
  get  "/auth/:slug/callback"    => "omniauth_sessions#callback",  as: :oidc_callback, constraints: { slug: /[a-z0-9-]+/ }
  get  "/auth/failure"           => "omniauth_sessions#failure",   as: :oidc_failure

  namespace :admin do
    resources :auth_providers, except: :show
    resources :api_tokens, only: %i[index new create destroy]
    root to: redirect("/admin/auth_providers")
  end

  namespace :api do
    namespace :v1 do
      get "whoami" => "whoami#show", as: :whoami
      resources :users, only: %i[index show create update destroy]
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
