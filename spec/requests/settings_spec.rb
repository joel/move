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
end
