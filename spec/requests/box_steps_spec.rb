# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Bulk box steps" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) } # creator → admin (editor) member

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/box_steps" do
    it "renders the distribution and the available step buttons for an editor" do
      create(:box, :with_room, move:, status: "packing")
      create(:box, :with_room, move:, status: "sealed")

      get move_box_steps_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("box_steps.show.title"))
      # A "Seal all" step (packing present) and a "Send in transit" step (sealed present).
      expect(response.body).to include(I18n.t("box_steps.show.steps.sealed.button", count: 1))
      expect(response.body).to include(I18n.t("box_steps.show.steps.in_transit.button", count: 1))
      # The POST target + the confirm guard are present on the buttons.
      expect(response.body).to include(move_box_steps_path(move))
      expect(response.body).to include(I18n.t("box_steps.show.steps.sealed.confirm"))
    end

    it "shows the empty state when no step has boxes waiting" do
      create(:box, :with_room, move:, status: "unpacked")

      get move_box_steps_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("box_steps.show.empty_title"))
    end

    it "forbids a viewer (mutating surface)" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      get move_box_steps_path(move)

      expect(response).to have_http_status(:forbidden)
    end

    it "redirects an archived move to the menu (read-only)" do
      archived = create(:move, :archived, created_by: user)

      get move_box_steps_path(archived)

      expect(response).to redirect_to(move_menu_path(archived))
      expect(flash[:alert]).to eq(I18n.t("moves.archived_alert"))
    end
  end

  describe "POST /moves/:move_id/box_steps" do
    it "transitions every box in the source state and redirects with a summary flash" do
      create_list(:box, 2, :with_room, move:, status: "packing")

      post move_box_steps_path(move), params: { to: "sealed" }

      expect(response).to redirect_to(move_box_steps_path(move))
      expect(flash[:notice]).to eq(
        I18n.t("box_steps.create.transitioned", count: 2, status: I18n.t("boxes.status.sealed"))
      )
      expect(move.boxes.where(status: "sealed").count).to eq(2)
    end

    it "reports skipped roomless boxes in the flash, sealing the rest" do
      create(:box, :with_room, move:, status: "packing", number: "1")
      create(:box, move:, status: "packing", room: nil, number: "2")

      post move_box_steps_path(move), params: { to: "sealed" }

      expect(flash[:notice]).to include(I18n.t("box_steps.skip_reason.room_required")).and include("2")
      expect(move.boxes.where(status: "sealed").count).to eq(1)
    end

    it "rejects an invalid step with an alert and no change" do
      create(:box, :with_room, move:, status: "sealed")

      post move_box_steps_path(move), params: { to: "packing" }

      expect(response).to redirect_to(move_box_steps_path(move))
      expect(flash[:alert]).to eq(I18n.t("box_steps.create.invalid_step"))
      expect(move.boxes.where(status: "packing")).to be_empty
    end

    it "does not transition on an archived move (read-only redirect)" do
      archived = create(:move, :archived, created_by: user)
      box = create(:box, :with_room, move: archived, status: "packing")

      post move_box_steps_path(archived), params: { to: "sealed" }

      expect(response).to redirect_to(move_menu_path(archived))
      expect(box.reload.status).to eq("packing")
    end

    it "forbids a viewer" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      post move_box_steps_path(move), params: { to: "sealed" }

      expect(response).to have_http_status(:forbidden)
    end
  end
end
