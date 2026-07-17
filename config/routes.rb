Rails.application.routes.draw do
  # Google One Tap credential endpoint (active when GOOGLE_CLIENT_ID is set)
  post "auth/google/one_tap", to: "google_one_tap_sessions#create"
  # #280 — apex->subdomain session handoff. Cookies are host-only, so the apex
  # session does not travel to <slug>.<zone>; the apex mints a single-use token
  # and redirects here, where the subdomain exchanges it for its own session.
  # Lives on the tenant subdomain (the controller validates against the tenant).
  get "session/handoff", to: "session_handoffs#show", as: :session_handoff
  # D14 (#608) — Move invitation acceptance. Lives on the APEX host (the
  # recipient has no tenant access until they accept); the raw token rides the
  # QUERY string (never the path) so config.filter_parameters' `token` rule
  # redacts it from request logs — the digest-only storage guarantee would be
  # hollow if every landing hit logged the raw value. GET = landing (anonymous
  # or authenticated), POST = accept (requires the authenticated invited email;
  # the token arrives as a filtered form param).
  get "invitations", to: "invitation_acceptances#show", as: :invitation_acceptance
  post "invitations", to: "invitation_acceptances#create"
  # #369 — terms-agreement gate. Authenticated accounts must accept the current
  # terms version before any tenant surface; TenantController redirects here until
  # they do. Lives on the tenant subdomain (the controller is tenant-resolved).
  get "agreement", to: "agreements#show", as: :agreement
  post "agreement", to: "agreements#accept", as: :accept_agreement
  resource :account, only: %i[show update destroy]
  # D13 — MCP assistant endpoint. Tenant-scoped (resolved from the org subdomain
  # by the Apartment elevator) and authenticated by a per-Move Bearer integration
  # token, not a session. JSON-RPC over a single POST (no SSE session state).
  post "mcp", to: "mcp#handle"
  # MCP Direct Upload (#110): the client POSTs raw image bytes here (app-proxied
  # to storage, since SeaweedFS is internal-only); returns a Move-scoped signed_id.
  post "mcp/uploads", to: "mcp_uploads#create"
  # A1 — Create / select Move (entry screen on an Organization subdomain).
  # A2 — Boxes Home: the box list/grid is the hub of a Move.
  resources :moves, only: %i[index new create destroy] do
    # B1 — Box detail & lifecycle.
    resources :boxes, only: %i[index new create show edit update destroy] do
      member do
        patch :transition
        # One-tap "next box of the same size" from the box card (#658).
        post :duplicate
        # Phase A — manual fragile flag on the box (drives the FRAGILE label mark).
        patch :fragile, action: :set_fragile
        # B1 — seal-time "describe before sealing" modal frame (auto-suggests a
        # contents description). `description_suggestion` is the JSON the edit-form
        # ✨ button fetches to fill the field.
        get :seal
        get :description_suggestion
      end
      # B3 — Manual add item (scoped to the box it lands in).
      resources :items, only: %i[new create]
      # C2 — Per-photo review: walk the box's photos; each screen lists every item
      # detected in that photo as an editable field (rename auto-saves on blur),
      # with × to remove and "+ Add" for a missed item. Reviewing is explicit
      # (#660): "Mark as Reviewed" POSTs to mark_reviewed and advances; "Ignore"
      # (plain GET) only navigates — opening a photo changes nothing.
      get "review", to: "reviews#index", as: :review
      get "review/photo/:media_id", to: "reviews#photo", as: :review_photo
      post "review/photo/:media_id/mark_reviewed", to: "reviews#mark_reviewed", as: :review_mark_reviewed
      # Delete a whole photo (and its items) — packing only; reuses the review_photo
      # path with the DELETE verb.
      delete "review/photo/:media_id", to: "reviews#delete_photo"
      patch "review/photo/:media_id/items/:id/rename", to: "reviews#rename_item", as: :review_rename_item
      patch "review/photo/:media_id/items/:id/remove", to: "reviews#remove_item", as: :review_remove_item
      post "review/photo/:media_id/items", to: "reviews#add_item", as: :review_add_item
      # C3 — move a whole photo (and its co-located items) to another box (#317).
      patch "review/photo/:media_id/move", to: "reviews#move_photo", as: :review_move_photo
      # Retake — replace a photo's image in place (recover a corrupt master); any
      # phase, optional re-scan. (#577)
      post "review/photo/:media_id/retake", to: "reviews#retake_photo", as: :review_retake_photo
      # Recovery — a persistent entry point for an orphaned photo (recognition
      # failed or found nothing, so no item). Re-run recognition or hand off to the
      # manual add (B3). `state` is the polled status fragment.
      get "recovery/photo/:media_id", to: "recoveries#show", as: :recovery_photo
      get "recovery/photo/:media_id/state", to: "recoveries#state", as: :recovery_photo_state
      post "recovery/photo/:media_id/retry", to: "recoveries#retry", as: :recovery_photo_retry
      # B2 — Capture image & recognition. The session panel updates live over
      # ActionCable (#241); there is no polled fragment endpoint any more.
      get "capture", to: "captures#show", as: :capture
      post "capture", to: "captures#create"
      # Direct-upload presign (#572): tenant + membership + writable + capturable
      # gated (CapturesController before_actions), mints an R2 presigned PUT + a
      # Move-scoped signed_id so the browser uploads straight to R2 (not through the
      # app). Falls back to POST capture (server-proxied) when disabled/unavailable.
      post "capture/direct_upload", to: "captures#direct_upload", as: :capture_direct_upload
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
    resources :items, only: %i[show update destroy] do
      member do
        patch :move
        patch :mark_removed
        patch :restore
        # #416 — opt-in "✨ generate image" for a photo-less manual item.
        post :generate_image
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
    # Gallery — browse every captured (and AI-generated) photo across the whole
    # Move in one recent-first grid, filterable by room. Read-only; reached from
    # the Menu hub. A tile opens a client-side lightbox (the :detail variant).
    get "gallery", to: "galleries#index", as: :gallery
    # #633 — one item family in full (the gallery Groups drill-down): members
    # ordered by box for unpacking, each locating itself with a box/room chip.
    get "gallery/groups/:id", to: "gallery_groups#show", as: :gallery_group
    # #654 — Move-wide review queue: every photo still holding an unreviewed
    # co-located item, oldest first. "Review all" walks the C2 photo screen
    # across box boundaries (reviews#photo?queue=move).
    get "review", to: "review_queues#show", as: :review
    # F1 — Members & roles (admin-only). Add an existing Organization user, change
    # a member's role, or remove them. Role changes go through a member action.
    resources :members, only: %i[index create destroy] do
      member { patch :update_role }
    end
    # D14 (#608) — email invitations to this Move (admin-only). Pending
    # invitations are managed from the Members page; acceptance happens on the
    # APEX (see the top-level invitations/:token routes).
    resources :invitations, only: %i[create destroy] do
      member { post :resend }
    end
    # F2 — Volume & weight summary. Read-only aggregate for any Move member; the
    # unit-system toggle persists Move#unit_system (editors only, never archived).
    get "summary", to: "summaries#show", as: :summary
    patch "summary/unit_system", to: "summaries#update_unit_system", as: :summary_unit_system
    # G1 — Activity feed (append-only audit journal). Any member reads; Restore
    # (undelete) and Revert (undo the latest edit) are editor-only and dispatch to
    # the domain actions, keyed by the activity row so the UI stays declarative.
    get "activity", to: "activities#index", as: :activity
    post "activity/:id/restore", to: "activities#restore", as: :activity_restore
    post "activity/:id/revert", to: "activities#revert", as: :activity_revert
    # F3 — Menu hub + Settings/Assistant. The menu is the controls hub; settings
    # holds Move-level preferences (unit system, auto-confirm threshold — editors
    # only, never archived; theme is a client preference). Integration tokens are
    # the per-Move MCP credentials (admin-only create/revoke).
    get "menu", to: "menu#show", as: :menu
    # Phase 44 — Bulk box lifecycle steps. Reached from the Menu (editor-only).
    # `show` lists the state distribution + a confirm-guarded button per available
    # forward step; `create` advances every box in one source state through the
    # requested step (Boxes::BulkTransition, reusing the per-box TransitionStatus).
    get "box_steps", to: "box_steps#show", as: :box_steps
    post "box_steps", to: "box_steps#create"
    # E1 — Label Print: pick a box-number range (e.g. 2–5) and print all those
    # exterior labels in one PDF (labels_per_box pages per box). Reached from the Menu. The form
    # POSTs a run; the PDF is rendered in a background job with a live progress bar
    # (#303), then downloaded — no synchronous request-blocking render.
    get "label_print", to: "label_prints#show", as: :label_print
    resources :label_print_runs, path: "label_print/runs", only: %i[create show] do
      member { get :download }
    end
    get "settings", to: "settings#show", as: :settings
    patch "settings/unit_system", to: "settings#update_unit_system", as: :settings_unit_system
    patch "settings/auto_confirm_threshold", to: "settings#update_auto_confirm_threshold",
                                             as: :settings_auto_confirm_threshold
    # Phase 45 — how many identical exterior labels to print per box (1..10),
    # applied by both the single-box and bulk label prints. Editors only.
    patch "settings/labels_per_box", to: "settings#update_labels_per_box", as: :settings_labels_per_box
    # F3 / #242 — shared "AI Capability" keys (admin-only). One key per vendor,
    # set/removed independently of which feature uses it.
    patch "settings/provider_key", to: "settings#update_provider_key", as: :settings_provider_key
    delete "settings/provider_key/:provider",
           to: "settings#remove_provider_key", as: :settings_remove_provider_key
    # F3 / #185 — per-Move Recognition provider selector + model override (admin-only).
    patch "settings/recognition_provider",
          to: "settings#update_recognition_provider", as: :settings_recognition_provider
    # #232 — per-Move semantic-search (embedding) provider (admin-only). Switching it
    # re-embeds every item; #239 shows live progress.
    patch "settings/embedding_provider",
          to: "settings#update_embedding_provider", as: :settings_embedding_provider
    resources :integration_tokens, only: %i[create destroy]
  end
  get "welcome/home"

  # Internal design-system reference (Phase D0). Gated to local envs / admins
  # in the controller.
  get "style_guide", to: "style_guide#show"

  # Test-only login shortcut used by system specs (see TestSessionsController).
  get "test/login", to: "test_sessions#show" if Rails.env.test?

  # Lookbook (#530) — component browser / preview environment for the Phlex
  # Ui::* kit. Development-only: the gem lives in the :development group, so
  # the constant does not exist elsewhere. Reach it on the apex dev host
  # (https://move.move-easy.docker/lookbook — the tenant elevator keeps the
  # apex on the public schema). See doc/project/component-previews.md.
  mount Lookbook::Engine, at: "/lookbook" if Rails.env.development?
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # CSP violation report sink (#493). The report-only Content-Security-Policy points
  # `report-uri` here; browsers POST violations (unauthenticated) and the controller
  # logs a bounded summary. Top-level so it resolves on the apex and every subdomain.
  post "csp-violation-report", to: "csp_reports#create"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Dynamic PWA files from app/views/pwa/*. Served at the root path level so the
  # service worker's default scope is "/" (controls the whole app). The manifest
  # is linked from the Phlex Views::Layouts::ChromeHead (the head every real app
  # page uses) — NOT application.html.erb, which is unused.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "welcome#home"
end
