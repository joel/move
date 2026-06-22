# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings" do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin, unit_system: "metric") }

  before do
    stub_current_user(admin)
    stub_current_tenant("acme")
    allow(Apartment::Tenant).to receive(:current).and_return("acme")
  end

  describe "GET /moves/:move_id/settings" do
    it "renders the settings screen with interactive controls for an editor" do
      get move_settings_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings.show.recognition.threshold"))
      expect(response.body).to include("threshold") # slider Stimulus controller
      expect(response.body).to include('id="assistant"')
      # Phase 45 — the labels-per-box auto-submitting select is present for an editor.
      expect(response.body).to include(I18n.t("settings.show.preferences.labels_per_box"))
      expect(response.body).to include("settings/labels_per_box")
    end

    it "shows resolved values read-only for a viewer" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      get move_settings_path(move)

      expect(response).to have_http_status(:ok)
      # Viewers cannot manage tokens.
      expect(response.body).to include(I18n.t("integration_tokens.panel.admin_only"))
      # A viewer on an active Move is told it's view-only — never "archived"
      # (apostrophes render HTML-escaped, so match on the distinctive phrase).
      expect(response.body).to include("view-only access")
      expect(response.body).not_to include("is archived")
    end

    it "tells an editor on an archived move it is archived (not view-only)" do
      move.update!(status: "archived")

      get move_settings_path(move)

      expect(response.body).to include("is archived")
      expect(response.body).not_to include("view-only access")
    end

    it "404s a non-member" do
      stub_current_user(create(:user))

      get move_settings_path(move)

      expect(response).to have_http_status(:not_found)
    end

    it "renders the AI Capability keys masked, never leaking the raw key, for an admin (#242)" do
      move.update!(openai_api_key: "sk-supersecret-1234")

      get move_settings_path(move)

      expect(response.body).to include(I18n.t("settings.show.ai_capability.title"))
      expect(response.body).to include("••••1234") # last4 only
      expect(response.body).not_to include("sk-supersecret-1234")
      # Every key-holding vendor has a row.
      expect(response.body).to include(I18n.t("settings.show.ai_capability.providers.voyage"))
    end

    it "shows the active provider read-only (no key field, no AI Capability) for a contributor" do
      move.update!(recognition_provider: "openai", openai_api_key: "sk-supersecret-1234")
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      get move_settings_path(move)

      expect(response.body).to include(I18n.t("settings.show.recognition.providers.options.openai"))
      expect(response.body).not_to include('name="move[api_key]"')
      # No AI Capability write surface for a contributor.
      expect(response.body).not_to include(move_settings_provider_key_path(move))
      expect(response.body).not_to include("sk-supersecret-1234")
    end

    it "disables a keyless real provider in the selector and enables a keyed one (#242)" do
      move.update!(openai_api_key: "sk-live") # OpenAI keyed; Gemini/Anthropic not

      get move_settings_path(move)

      # Keyed → a real switch form; keyless → a disabled chip with the needs-key hint.
      expect(response.body).to include("action=\"#{move_settings_recognition_provider_path(move)}\"")
      expect(response.body).to include(I18n.t("settings.show.recognition.providers.needs_key"))
    end

    it "renders the panel_card bodies (recognition selector, threshold, search control), not empty cards (#242)" do
      get move_settings_path(move)

      expect(response.body).to include(I18n.t("settings.show.recognition.providers.provider_label")) # recognition selector
      expect(response.body).to include(I18n.t("settings.show.recognition.threshold")) # threshold block
      expect(response.body).to include('id="ai-embedding-control"') # search control
    end

    it "carries a provider's stored model override in its switch pill, so switching preserves it (#242)" do
      # OpenAI keyed with a saved override, but fake is active → the OpenAI pill is
      # a switch form that must resubmit gpt-5 (else switching clears the override).
      move.update!(recognition_provider: "fake", openai_api_key: "sk-live", openai_model: "gpt-5")

      get move_settings_path(move)

      expect(response.body).to include('name="move[model]"')
      expect(response.body).to include('value="gpt-5"')
    end

    it "renders the editable model field for an admin (#187)" do
      move.update!(recognition_provider: "openai", openai_api_key: "sk-live", openai_model: "gpt-5")

      get move_settings_path(move)

      expect(response.body).to include('name="move[model]"')
      expect(response.body).to include("gpt-5") # the override is shown
    end

    it "shows the resolved model read-only for a contributor (no model input)" do
      move.update!(recognition_provider: "openai", openai_api_key: "sk-live")
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      get move_settings_path(move)

      expect(response.body).to include(RecognitionProviders::Openai::DEFAULT_MODEL)
      expect(response.body).not_to include('name="move[model]"')
    end

    it "subscribes to the Move's indexing stream and renders the live control for an admin (#239)" do
      get move_settings_path(move)

      # Signed Turbo Stream source (ActionCable) + the broadcast-target region.
      expect(response.body).to include("<turbo-cable-stream-source")
      expect(response.body).to include('id="ai-embedding-control"')
    end

    it "labels the Semantic Search default 'Keyword only', not 'Off' (#248)" do
      get move_settings_path(move) # move defaults to embedding_provider fake

      expect(response.body).to include(I18n.t("settings.show.recognition.embeddings.options.fake"))
      expect(I18n.t("settings.show.recognition.embeddings.options.fake")).to eq("Keyword only")
      expect(response.body).to include("Keyword search is always on")
    end

    it "locks the embedding selector while a run is in progress (#239)" do
      create(:indexing_run, :processing, move:, total_count: 4, completed_count: 1)

      get move_settings_path(move)

      expect(response.body).to include(
        I18n.t("settings.show.recognition.embeddings.indexing.in_progress", done: 1, total: 4)
      )
      # Locked note shown (apostrophe renders HTML-escaped, so match the phrase).
      expect(response.body).to include("change the provider while indexing is running")
    end
  end

  describe "PATCH /moves/:move_id/settings/unit_system" do
    it "persists the unit system for an editor" do
      patch move_settings_unit_system_path(move), params: { move: { unit_system: "imperial" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.unit_system).to eq("imperial")
    end

    it "forbids a viewer" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      patch move_settings_unit_system_path(move), params: { move: { unit_system: "imperial" } }

      expect(response).to have_http_status(:forbidden)
      expect(move.reload.unit_system).to eq("metric")
    end
  end

  describe "PATCH /moves/:move_id/settings/auto_confirm_threshold" do
    it "persists a valid threshold for an editor" do
      patch move_settings_auto_confirm_threshold_path(move), params: { move: { auto_confirm_threshold: "0.5" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.auto_confirm_threshold).to eq(0.5)
    end

    it "rejects an out-of-range threshold without changing the move" do
      patch move_settings_auto_confirm_threshold_path(move), params: { move: { auto_confirm_threshold: "2" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.auto_confirm_threshold).to eq(0.8)
    end

    it "refuses changes on an archived move" do
      move.update!(status: "archived")

      patch move_settings_auto_confirm_threshold_path(move), params: { move: { auto_confirm_threshold: "0.5" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.auto_confirm_threshold).to eq(0.8)
    end
  end

  describe "PATCH /moves/:move_id/settings/labels_per_box (Phase 45)" do
    it "persists a valid value for an editor" do
      patch move_settings_labels_per_box_path(move), params: { move: { labels_per_box: "5" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.labels_per_box).to eq(5)
    end

    it "rejects an out-of-range value without changing the move" do
      patch move_settings_labels_per_box_path(move), params: { move: { labels_per_box: "0" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.labels_per_box).to eq(2)
    end

    it "forbids a viewer" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      patch move_settings_labels_per_box_path(move), params: { move: { labels_per_box: "5" } }

      expect(response).to have_http_status(:forbidden)
      expect(move.reload.labels_per_box).to eq(2)
    end

    it "refuses changes on an archived move" do
      move.update!(status: "archived")

      patch move_settings_labels_per_box_path(move), params: { move: { labels_per_box: "5" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.labels_per_box).to eq(2)
    end
  end

  describe "PATCH /moves/:move_id/settings/provider_key (#242)" do
    it "stores a vendor key for an admin" do
      patch move_settings_provider_key_path(move), params: { move: { provider: "anthropic", api_key: "a-live" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.anthropic_api_key).to eq("a-live")
    end

    it "refreshes the AI panels in place (no reload) for a Turbo request (#260)" do
      patch move_settings_provider_key_path(move),
            params: { move: { provider: "anthropic", api_key: "a-live" } }, as: :turbo_stream

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="#{Views::Settings::AiCapabilityPanel::ID}"))
      expect(response.body).to include(%(target="#{Views::Settings::RecognitionProviderPanel::ID}"))
      expect(response.body).to include(%(target="#{Views::Settings::EmbeddingPanelBody::ID}"))
      expect(move.reload.anthropic_api_key).to eq("a-live")
    end

    it "streams a toast (not silent) when a Turbo submit fails on a blank key (#260)" do
      patch move_settings_provider_key_path(move),
            params: { move: { provider: "openai", api_key: "  " } }, as: :turbo_stream

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="#{Components::FlashToasts::ID}"))
      expect(response.body).to include(I18n.t("settings.update_provider_key.api_key_required"))
      expect(move.reload.openai_api_key).to be_nil
    end

    it "forbids a contributor (keys are admin-only)" do
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      patch move_settings_provider_key_path(move), params: { move: { provider: "openai", api_key: "sk-live" } }

      expect(response).to have_http_status(:forbidden)
      expect(move.reload.openai_api_key).to be_nil
    end
  end

  describe "DELETE /moves/:move_id/settings/provider_key/:provider (#242)" do
    it "removes the stored key for an admin" do
      move.update!(openai_api_key: "sk-live")

      delete move_settings_remove_provider_key_path(move, provider: "openai")

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.openai_api_key).to be_nil
    end

    it "refreshes the AI panels in place (no reload) for a Turbo request (#260)" do
      move.update!(openai_api_key: "sk-live")

      delete move_settings_remove_provider_key_path(move, provider: "openai"), as: :turbo_stream

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(%(target="#{Views::Settings::AiCapabilityPanel::ID}"))
      expect(response.body).to include(%(target="#{Views::Settings::EmbeddingPanelBody::ID}"))
      expect(move.reload.openai_api_key).to be_nil
    end

    it "forbids a contributor" do
      move.update!(openai_api_key: "sk-live")
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      delete move_settings_remove_provider_key_path(move, provider: "openai")

      expect(response).to have_http_status(:forbidden)
      expect(move.reload.openai_api_key).to eq("sk-live")
    end
  end

  describe "PATCH /moves/:move_id/settings/recognition_provider" do
    it "switches the provider for an admin (key already stored)" do
      move.update!(openai_api_key: "sk-live")

      patch move_settings_recognition_provider_path(move), params: { move: { recognition_provider: "openai" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.recognition_provider).to eq("openai")
    end

    it "refreshes the AI panels in place (no reload) for a Turbo request (#260)" do
      move.update!(openai_api_key: "sk-live")

      patch move_settings_recognition_provider_path(move),
            params: { move: { recognition_provider: "openai" } }, as: :turbo_stream

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="replace"')
      expect(response.body).to include(%(target="#{Views::Settings::RecognitionProviderPanel::ID}"))
      expect(move.reload.recognition_provider).to eq("openai")
    end

    it "persists a model override alongside the provider (#187)" do
      move.update!(openai_api_key: "sk-live")

      patch move_settings_recognition_provider_path(move),
            params: { move: { recognition_provider: "openai", model: "gpt-5" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.openai_model).to eq("gpt-5")
    end

    it "redirects with an error when a real provider is selected without a stored key" do
      patch move_settings_recognition_provider_path(move), params: { move: { recognition_provider: "gemini" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.recognition_provider).to eq("fake")
    end
  end

  describe "PATCH /moves/:move_id/settings/embedding_provider (#232)" do
    before { allow(Search::RefreshDocumentJob).to receive(:perform_later) }

    it "turns semantic search on for an admin and enqueues a reindex (html fallback redirects)" do
      item = create(:item, move:)

      patch move_settings_embedding_provider_path(move), params: { move: { embedding_provider: "openai" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.embedding_provider).to eq("openai")
      expect(Search::RefreshDocumentJob).to have_received(:perform_later).with(item.id, hash_including(:tenant))
    end

    it "responds with a scoped Turbo Stream (no full-page reload) for a Turbo request (#247)" do
      patch move_settings_embedding_provider_path(move),
            params: { move: { embedding_provider: "openai" } }, as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      # Replaces only the panel body, not a navigation.
      expect(response.body).to include(%(target="#{Views::Settings::EmbeddingPanelBody::ID}"))
      expect(response.body).to include('action="replace"')
      expect(move.reload.embedding_provider).to eq("openai")
    end

    it "forbids a contributor (semantic search is admin-only)" do
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      patch move_settings_embedding_provider_path(move), params: { move: { embedding_provider: "openai" } }

      expect(response).to have_http_status(:forbidden)
      expect(move.reload.embedding_provider).to eq("fake")
    end

    it "rejects an unknown option without changing the move" do
      patch move_settings_embedding_provider_path(move), params: { move: { embedding_provider: "word2vec" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.embedding_provider).to eq("fake")
    end
  end
end
