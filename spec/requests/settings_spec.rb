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
end
