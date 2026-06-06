require "rails_helper"

RSpec.describe "Boxes" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    # Pretend we are on an Organization subdomain (the elevator does this in
    # real requests); Move data resolves against the public template here.
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/boxes" do
    it "renders the boxes grid with the move name and per-box data" do
      room = create(:room, move:, name: "Kitchen")
      create(:box, move:, number: "1", room:, status: "sealed")

      get move_boxes_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Boxes").and include(move.name)
      expect(response.body).to include("Kitchen").and include("Box 01")
    end

    it "renders the empty state when the move has no boxes" do
      get move_boxes_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("boxes.empty.title"))
    end

    it "filters boxes by room" do
      kitchen = create(:room, move:, name: "Kitchen")
      bedroom = create(:room, move:, name: "Bedroom")
      create(:box, move:, number: "1", room: kitchen)
      create(:box, move:, number: "2", room: bedroom)

      get move_boxes_path(move, room_id: kitchen.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Kitchen")
      expect(response.body).not_to include("Box 02")
    end

    it "treats a malformed room_id as a cleared filter (no error)" do
      create(:box, move:, number: "1")

      get move_boxes_path(move, room_id: "not-a-uuid")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Box 01")
    end
  end

  describe "GET /moves/:move_id/boxes/new" do
    it "renders the add-box form" do
      get new_move_box_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("boxes.form.submit"))
    end

    it "redirects to the boxes home for an archived (read-only) move" do
      archived = create(:move, :archived, created_by: user)

      get new_move_box_path(archived)

      expect(response).to redirect_to(move_boxes_path(archived))
    end
  end

  describe "POST /moves/:move_id/boxes" do
    it "creates a box with an auto number and redirects" do
      expect do
        post move_boxes_path(move), params: { box: { room_name: "Kitchen" } }
      end.to change(move.boxes, :count).by(1)

      expect(response).to redirect_to(move_boxes_path(move))
      expect(move.boxes.last.room.name).to eq("Kitchen")
    end

    it "re-renders the form with errors for an invalid number" do
      expect do
        post move_boxes_path(move), params: { box: { number: "A1" } }
      end.not_to change(Box, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses to create on an archived move" do
      archived = create(:move, :archived, created_by: user)

      expect do
        post move_boxes_path(archived), params: { box: {} }
      end.not_to change(Box, :count)

      expect(response).to redirect_to(move_boxes_path(archived))
    end
  end

  describe "without a tenant (apex/public)" do
    it "returns 404 (non-disclosing)" do
      stub_current_tenant(nil)

      get move_boxes_path(move)

      expect(response).to have_http_status(:not_found)
    end
  end
end
