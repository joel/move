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
      # B3 — Manual add item (scoped to the box it lands in).
      resources :items, only: %i[new create]
      # C1/C2 — Review flow: queue (index) + item-by-item (show) + per-suggestion
      # actions, scoped to the box being finalized.
      resources :recognition_suggestions, only: %i[index show], path: "review", as: :review do
        member do
          patch :keep
          patch :correct
          patch :mark_false_positive
        end
      end
      # B2 — Capture image & recognition. `session` is the polled session panel.
      get "capture", to: "captures#show", as: :capture
      post "capture", to: "captures#create"
      get "capture/session", to: "captures#session_panel", as: :capture_session
      post "capture/retry", to: "captures#retry_recognition", as: :capture_retry
      # E1 — Box label (A7, opaque) and authenticated manifest (A4) as inline PDFs.
      get "label", to: "labels#show", as: :label
      get "manifest", to: "manifests#show", as: :manifest
      # E3 — Unpacking mode: destination-side checklist (box in `unpacking`) and
      # the "box unpacked" celebration (box in `unpacked`). Per-item remove/restore
      # toggles, `complete` (cascade to unpacked), `reopen` (Undo back to unpacking).
      get "unpacking", to: "unpacking#show", as: :unpacking
      patch "unpacking/complete", to: "unpacking#complete", as: :unpacking_complete
      patch "unpacking/reopen", to: "unpacking#reopen", as: :unpacking_reopen
      patch "unpacking/items/:item_id/remove", to: "unpacking#remove", as: :unpacking_remove
      patch "unpacking/items/:item_id/restore", to: "unpacking#restore", as: :unpacking_restore
    end
    # E2 — QR scanner (live camera + manual entry) and token resolution, both in
    # the Move app shell. Resolution looks the box up by qr_token across the
    # tenant, so a token from another org's schema is simply absent → a
    # non-disclosing "unrecognized" state.
    get "scan", to: "scans#show", as: :scan
    get "scan/:token", to: "scans#resolve", as: :scan_resolve,
                       constraints: { token: /[A-Za-z0-9_-]+/ }
    # C3 — Item detail / edit. Scoped to the Move (not the box) so the record
    # survives a box-to-box move; presence/box changes via member actions.
    resources :items, only: %i[show update] do
      member do
        patch :move
        patch :mark_removed
        patch :restore
      end
    end
    # D2 — Controlled vocabularies (categories / tags / rooms). One controller
    # serves all three siblings; the `:kind` segment is constrained to the
    # registry so an unknown kind 404s at the routing layer.
    kind = { kind: /categories|tags|rooms/ }
    get "vocabularies/:kind", to: "vocabularies#index", as: :vocabularies, constraints: kind
    post "vocabularies/:kind", to: "vocabularies#create", constraints: kind
    patch "vocabularies/:kind/:id", to: "vocabularies#update", as: :vocabulary, constraints: kind
    delete "vocabularies/:kind/:id", to: "vocabularies#destroy", constraints: kind
    # D1 — Hybrid search over the Move's items (full-text + trigram + pgvector).
    get "search", to: "searches#index", as: :search
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
