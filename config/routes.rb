Rails.application.routes.draw do
  # Google One Tap credential endpoint (active when GOOGLE_CLIENT_ID is set)
  post "auth/google/one_tap", to: "google_one_tap_sessions#create"
  resource :account, only: %i[show edit update destroy]
  # A1 — Create / select Move (entry screen on an Organization subdomain).
  # A2 — Boxes Home: the box list/grid is the hub of a Move.
  resources :moves, only: %i[index new create] do
    # B1 — Box detail & lifecycle.
    resources :boxes, only: %i[index new create show edit update] do
      member { patch :transition }
      # B2 — Capture image & recognition. `session` is the polled session panel.
      get "capture", to: "captures#show", as: :capture
      post "capture", to: "captures#create"
      get "capture/session", to: "captures#session_panel", as: :capture_session
      post "capture/retry", to: "captures#retry_recognition", as: :capture_retry
    end
  end
  resources :posts
  resources :users
  get "welcome/home"

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

  # Defines the root path route ("/")
  root "welcome#home"
end
