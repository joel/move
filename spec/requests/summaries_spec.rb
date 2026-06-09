# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Summaries" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) } # creator → admin (editor) member

  before do
    stub_current_user(user)
    # Pretend we are on an Organization subdomain (the elevator does this in
    # real requests); Move data resolves against the public template here.
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/summary" do
    it "renders totals and the per-room breakdown for a member" do
      kitchen = create(:room, move:, name: "Kitchen")
      create(:box, move:, room: kitchen, length_cm: 40, width_cm: 30, height_cm: 25, weight_kg: 8)

      get move_summary_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Move Summary").and include(move.name)
      expect(response.body).to include("Kitchen")
      expect(response.body).to include(I18n.t("summaries.show.room_breakdown"))
    end

    it "shows the incomplete-data banner when a box is missing dimensions" do
      create(:box, move:) # packing, no dimensions

      get move_summary_path(move)

      expect(response.body).to include(I18n.t("summaries.show.missing_warning_title"))
    end

    it "omits the banner when every box has dimensions" do
      create(:box, move:, length_cm: 40, width_cm: 30, height_cm: 25)

      get move_summary_path(move)

      expect(response.body).not_to include(I18n.t("summaries.show.missing_warning_title"))
    end

    it "renders the empty state when the move has no boxes" do
      get move_summary_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("summaries.show.empty_title"))
    end

    it "404s a non-member non-disclosingly" do
      stub_current_user(create(:user))

      get move_summary_path(move)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /moves/:move_id/summary/unit_system" do
    it "persists the new unit system for an editor" do
      patch move_summary_unit_system_path(move), params: { move: { unit_system: "imperial" } }

      expect(response).to redirect_to(move_summary_path(move))
      expect(move.reload.unit_system).to eq("imperial")
    end

    it "rejects an unknown unit system without changing the move" do
      patch move_summary_unit_system_path(move), params: { move: { unit_system: "furlongs" } }

      expect(move.reload.unit_system).to eq("metric")
    end

    it "forbids a viewer (read-only role)" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      patch move_summary_unit_system_path(move), params: { move: { unit_system: "imperial" } }

      expect(response).to have_http_status(:forbidden)
      expect(move.reload.unit_system).to eq("metric")
    end

    it "refuses to change an archived move (read-only)" do
      archived = create(:move, :archived, created_by: user)

      patch move_summary_unit_system_path(archived), params: { move: { unit_system: "imperial" } }

      expect(response).to redirect_to(move_summary_path(archived))
      expect(archived.reload.unit_system).to eq("metric")
    end
  end
end
