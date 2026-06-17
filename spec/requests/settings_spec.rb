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

    it "renders the recognition provider panel masked, never leaking the raw key, for an admin" do
      move.update!(recognition_provider: "openai", openai_api_key: "sk-supersecret-1234")

      get move_settings_path(move)

      expect(response.body).to include(I18n.t("settings.show.recognition.providers.subtitle"))
      expect(response.body).to include("••••••••1234") # last4 only
      expect(response.body).not_to include("sk-supersecret-1234")
    end

    it "shows the active provider read-only (no key field) for a contributor" do
      move.update!(recognition_provider: "openai", openai_api_key: "sk-supersecret-1234")
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      get move_settings_path(move)

      expect(response.body).to include(I18n.t("settings.show.recognition.providers.options.openai"))
      expect(response.body).not_to include('name="move[api_key]"')
      expect(response.body).not_to include("sk-supersecret-1234")
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

  describe "PATCH /moves/:move_id/settings/recognition_provider" do
    it "sets the provider and stores the key for an admin" do
      patch move_settings_recognition_provider_path(move),
            params: { move: { recognition_provider: "openai", api_key: "sk-live" } }

      expect(response).to redirect_to(move_settings_path(move))
      move.reload
      expect(move.recognition_provider).to eq("openai")
      expect(move.openai_api_key).to eq("sk-live")
    end

    it "persists a model override submitted alongside the provider (#187)" do
      patch move_settings_recognition_provider_path(move),
            params: { move: { recognition_provider: "openai", api_key: "sk-live", model: "gpt-5" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.openai_model).to eq("gpt-5")
    end

    it "forbids a contributor (keys are admin-only)" do
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      patch move_settings_recognition_provider_path(move),
            params: { move: { recognition_provider: "openai", api_key: "sk-live" } }

      expect(response).to have_http_status(:forbidden)
      expect(move.reload.recognition_provider).to eq("fake")
    end

    it "redirects with an error when a real provider is selected without a key" do
      patch move_settings_recognition_provider_path(move),
            params: { move: { recognition_provider: "gemini", api_key: "" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.recognition_provider).to eq("fake")
    end
  end

  describe "DELETE /moves/:move_id/settings/recognition_provider/:provider" do
    it "removes the stored key for an admin" do
      move.update!(recognition_provider: "openai", openai_api_key: "sk-live")

      delete move_settings_remove_recognition_key_path(move, provider: "openai")

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.openai_api_key).to be_nil
    end

    it "forbids a contributor" do
      move.update!(openai_api_key: "sk-live")
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      delete move_settings_remove_recognition_key_path(move, provider: "openai")

      expect(response).to have_http_status(:forbidden)
      expect(move.reload.openai_api_key).to eq("sk-live")
    end
  end

  describe "PATCH /moves/:move_id/settings/embedding_provider (#232)" do
    before { allow(Search::RefreshDocumentJob).to receive(:perform_later) }

    it "turns semantic search on for an admin and enqueues a reindex" do
      item = create(:item, move:)

      patch move_settings_embedding_provider_path(move), params: { move: { embedding_provider: "openai" } }

      expect(response).to redirect_to(move_settings_path(move))
      expect(move.reload.embedding_provider).to eq("openai")
      expect(Search::RefreshDocumentJob).to have_received(:perform_later).with(item.id, hash_including(:tenant))
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
