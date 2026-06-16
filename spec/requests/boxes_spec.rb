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

    it "offers reuse-dimensions chips when the move has dimensioned boxes" do
      create_list(:box, 2, move:, length_cm: 40, width_cm: 30, height_cm: 25)

      get new_move_box_path(move)

      expect(response.body).to include(I18n.t("boxes.form.reuse_dimensions"))
      expect(response.body).to include("40 × 30 × 25 cm")
      expect(response.body).to include('data-dimension-presets-target="chip"')
    end

    it "omits the reuse-dimensions block when no box has dimensions" do
      create(:box, move:) # dimensionless

      get new_move_box_path(move)

      expect(response.body).not_to include(I18n.t("boxes.form.reuse_dimensions"))
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

    it "persists a description submitted with the form" do
      post move_boxes_path(move), params: { box: { room_name: "Kitchen", description: "Pots and pans" } }

      expect(move.boxes.last.description).to eq("Pots and pans")
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

    it "links an item-backed gallery photo to its review, opting out of Turbo prefetch" do
      box = create(:box, move:, number: "1")
      reviewable = create(:media, move:, box:)
      create(:item, move:, box:, source_media: reviewable, name: "Lamp")
      empty_photo = create(:media, move:, box:) # no items → absent from the review walk

      get move_box_path(move, box)

      # #162 — item-backed photo links to review; prefetch off so a hover can't
      # silently mark it reviewed. An item-less photo must NOT link (would render
      # a "Photo 1 of 0" dead end).
      expect(response.body).to include(%(href="#{move_box_review_photo_path(move, box, media_id: reviewable.id)}"))
      expect(response.body).to include('data-turbo-prefetch="false"')
      expect(response.body).not_to include(move_box_review_photo_path(move, box, media_id: empty_photo.id))
    end

    it "links a settled orphaned photo (failed) to recovery, but not one still in flight" do
      box = create(:box, move:, number: "1")
      failed = create(:media, move:, box:)
      create(:recognition_run, :failed, move:, box:, media: failed)
      in_flight = create(:media, move:, box:)
      create(:recognition_run, :processing, move:, box:, media: in_flight)

      get move_box_path(move, box)

      expect(response.body).to include(%(href="#{move_box_recovery_photo_path(move, box, media_id: failed.id)}"))
      expect(response.body).not_to include(move_box_recovery_photo_path(move, box, media_id: in_flight.id))
    end

    it "does not mark a photo recoverable once its recognized item moved to another box" do
      box = create(:box, move:, number: "1")
      other = create(:box, move:, number: "9")
      photo = create(:media, move:, box:)
      create(:recognition_run, :failed, move:, box:, media: photo)
      # Item recognized from this photo but now living in another box (source_media
      # is stable across the move) — the photo is not orphaned.
      create(:item, move:, box: other, source_media: photo, name: "Lamp")

      get move_box_path(move, box)

      expect(response.body).not_to include(move_box_recovery_photo_path(move, box, media_id: photo.id))
    end

    it "does not mark a conflict-only photo (suggestions, no item) as recoverable" do
      box = create(:box, move:, number: "1")
      photo = create(:media, move:, box:)
      run = create(:recognition_run, :succeeded, move:, box:, media: photo)
      create(:recognition_suggestion, :conflict, move:, box:, media: photo, recognition_run: run)

      get move_box_path(move, box)

      expect(response.body).not_to include(move_box_recovery_photo_path(move, box, media_id: photo.id))
    end
  end

  describe "GET /moves/:move_id/boxes/:id/edit" do
    it "excludes the edited box's own size from the reuse-dimensions chips" do
      edited = create(:box, move:, number: "1", length_cm: 99, width_cm: 99, height_cm: 99)
      create(:box, move:, number: "2", length_cm: 40, width_cm: 30, height_cm: 25)
      create(:box, move:, number: "3", length_cm: 40, width_cm: 30, height_cm: 25)

      get edit_move_box_path(move, edited)

      expect(response.body).to include("40 × 30 × 25 cm")
      expect(response.body).not_to include("99 × 99 × 99 cm")
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

    it "updates the description" do
      box = create(:box, move:, number: "1", description: "Old")

      patch move_box_path(move, box), params: { box: { description: "New summary" } }

      expect(box.reload.description).to eq("New summary")
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

    it "persists a description supplied at seal time (one transaction)" do
      box = create(:box, :with_room, move:, number: "1", status: "packing")

      patch transition_move_box_path(move, box),
            params: { to: "sealed", box: { description: "Clothes, Books" } }

      expect(box.reload.status).to eq("sealed")
      expect(box.description).to eq("Clothes, Books")
    end

    it "leaves the description untouched on a non-seal transition" do
      box = create(:box, :with_room, move:, number: "1", status: "sealed", description: "Kept")

      patch transition_move_box_path(move, box), params: { to: "in_transit", box: { description: "x" } }

      expect(box.reload.description).to eq("Kept")
    end
  end

  describe "GET /moves/:move_id/boxes/:id/seal" do
    it "renders the seal-modal frame with an auto-suggested description" do
      box = create(:box, :with_room, move:, number: "1", status: "packing")
      cat = create(:category, move:, name: "Kitchenware")
      create(:item, move:, box:, name: "Mug", category: cat)

      get seal_move_box_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("boxes.seal.title"))
      expect(response.body).to include("Kitchenware") # deterministic suggestion (fake provider)
    end

    it "is unprocessable for a box that cannot be sealed" do
      box = create(:box, :with_room, move:, number: "1", status: "in_transit")

      get seal_move_box_path(move, box)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /moves/:move_id/boxes/:id/description_suggestion" do
    it "returns the suggested description as JSON" do
      box = create(:box, :with_room, move:, number: "1", status: "packing")
      cat = create(:category, move:, name: "Books")
      create(:item, move:, box:, name: "Novel", category: cat)

      get description_suggestion_move_box_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["description"]).to eq("Books")
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

    # The AI-suggestion endpoints can spend the Move's vendor quota, so a viewer
    # must not be able to trigger them even by hitting the URL directly.
    it "forbids a viewer from the AI suggestion endpoints (403)" do
      box = create(:box, :with_room, move:, number: "1", status: "packing")
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      get description_suggestion_move_box_path(move, box)
      expect(response).to have_http_status(:forbidden)

      get seal_move_box_path(move, box)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
