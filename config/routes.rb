Rails.application.routes.draw do
  # Google One Tap credential endpoint (active when GOOGLE_CLIENT_ID is set)
  post "auth/google/one_tap", to: "google_one_tap_sessions#create"
  resource :account, only: %i[show edit update destroy]
  resources :posts
  resources :users
  get "welcome/home"

  # Onboarding: create the first Organization after signup (apex host).
  resource :onboarding, only: %i[new create], controller: "onboarding"

  # Internal design-system reference (Phase D0). Gated to local envs / admins
  # in the controller.
  get "style_guide", to: "style_guide#show"

  # Test-only login shortcut used by system specs (see TestSessionsController).
  get "test/login", to: "test_sessions#show" if Rails.env.test?
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Root: on an org subdomain, the tenant home; on the apex, the welcome page.
  # (PR2 replaces the tenant root with the A1 Move selector.)
  constraints(->(request) { TenantHost.tenant?(request.host) }) do
    root to: "organizations/home#show", as: :tenant_root
  end

  # Defines the root path route ("/")
  root "welcome#home"
end
