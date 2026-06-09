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

  describe "GET /moves/:move_id/boxes/:id" do
    it "renders the box detail with identity, dimensions and volume" do
      box = create(:box, :with_dimensions, move:, number: "1",
                                           room: create(:room, move:, name: "Kitchen"))

      get move_box_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Box #001").and include("Kitchen")
      expect(response.body).to include("40 × 30 × 25 cm").and include("0.030 m³")
    end
  end

  describe "PATCH /moves/:move_id/boxes/:id" do
    it "updates the box and redirects to its detail" do
      box = create(:box, move:, number: "1")

      patch move_box_path(move, box), params: { box: { weight_kg: 9, room_name: "Garage" } }

      expect(response).to redirect_to(move_box_path(move, box))
      expect(box.reload.weight_kg).to eq(9)
      expect(box.room.name).to eq("Garage")
    end

    it "re-renders the form with errors for an invalid number" do
      box = create(:box, move:, number: "1")

      patch move_box_path(move, box), params: { box: { number: "A1" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(box.reload.number).to eq("1")
    end
  end

  describe "PATCH /moves/:move_id/boxes/:id/transition" do
    it "seals a box that has a room" do
      box = create(:box, :with_room, move:, number: "1", status: "packing")

      patch transition_move_box_path(move, box), params: { to: "sealed" }

      expect(response).to redirect_to(move_box_path(move, box))
      expect(box.reload.status).to eq("sealed")
    end

    it "refuses to seal a box without a room and keeps it packing" do
      box = create(:box, move:, number: "1", status: "packing", room: nil)

      patch transition_move_box_path(move, box), params: { to: "sealed" }

      expect(response).to redirect_to(move_box_path(move, box))
      expect(box.reload.status).to eq("packing")
      follow_redirect!
      expect(response.body).to include(I18n.t("boxes.transition.room_required"))
    end

    it "rejects an illegal transition" do
      box = create(:box, :with_room, move:, number: "1", status: "packing")

      patch transition_move_box_path(move, box), params: { to: "unpacked" }

      expect(box.reload.status).to eq("packing")
    end

    it "is blocked on an archived move" do
      archived = create(:move, :archived, created_by: user)
      box = create(:box, :with_room, move: archived, number: "1", status: "packing")

      patch transition_move_box_path(archived, box), params: { to: "sealed" }

      expect(response).to redirect_to(move_boxes_path(archived))
      expect(box.reload.status).to eq("packing")
    end
  end

  describe "without a tenant (apex/public)" do
    it "returns 404 (non-disclosing)" do
      stub_current_tenant(nil)

      get move_boxes_path(move)

      expect(response).to have_http_status(:not_found)
    end
  end

  # D11 — mutation is gated on the editor role via ActionPolicy
  # (MovePolicy#edit_contents?, checked in require_writable_move!).
  describe "role enforcement on mutation" do
    it "forbids a viewer from creating a box (403)" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      expect do
        post move_boxes_path(move), params: { box: { number: "9" } }
      end.not_to change(move.boxes, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "lets a contributor create a box" do
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      expect do
        post move_boxes_path(move), params: { box: { number: "9" } }
      end.to change(move.boxes, :count).by(1)
    end
  end
end
