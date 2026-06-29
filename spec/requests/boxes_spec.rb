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

    it "defaults to recency order so the newest box is first (#336)" do
      create(:box, move:, number: "5", created_at: 2.days.ago) # older
      create(:box, move:, number: "1") # created now → newer

      get move_boxes_path(move)

      # The newer box (Box 01) sorts above the older one despite its lower number.
      expect(response.body.index("Box 01")).to be < response.body.index("Box 05")
    end

    it "orders by box number ascending when ?sort=number" do
      create(:box, move:, number: "2")
      create(:box, move:, number: "1")

      get move_boxes_path(move, sort: "number")

      expect(response.body.index("Box 01")).to be < response.body.index("Box 02")
    end

    it "orders by weight (heaviest first, unweighed last) when ?sort=weight" do
      create(:box, move:, number: "1", weight_kg: 5)
      create(:box, move:, number: "2", weight_kg: 20)
      create(:box, move:, number: "3") # no weight → NULLS LAST

      get move_boxes_path(move, sort: "weight")

      body = response.body
      expect(body.index("Box 02")).to be < body.index("Box 01")
      expect(body.index("Box 01")).to be < body.index("Box 03")
    end

    it "orders by volume (largest first, dimensionless last) when ?sort=size" do
      create(:box, move:, number: "1", length_cm: 10, width_cm: 10, height_cm: 10) # 1000
      create(:box, move:, number: "2", length_cm: 20, width_cm: 20, height_cm: 20) # 8000
      create(:box, move:, number: "3") # no dimensions → NULLS LAST

      get move_boxes_path(move, sort: "size")

      body = response.body
      expect(body.index("Box 02")).to be < body.index("Box 01")
      expect(body.index("Box 01")).to be < body.index("Box 03")
    end

    it "falls back to the default order for an unknown ?sort=" do
      create(:box, move:, number: "1")

      get move_boxes_path(move, sort: "nonsense")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Box 01")
    end

    it "keeps the active sort when switching room filters" do
      kitchen = create(:room, move:, name: "Kitchen")
      create(:box, move:, number: "1", room: kitchen)

      get move_boxes_path(move, sort: "weight")

      # The room-filter chip links carry the non-default sort so it survives.
      expect(response.body).to include("room_id=#{kitchen.id}").and include("sort=weight")
    end

    it "keeps the room filter chips when a filtered room has no boxes" do
      create(:room, move:, name: "Kitchen")
      empty_room = create(:room, move:, name: "Attic")
      create(:box, move:, number: "1", room: create(:room, move:, name: "Garage"))

      get move_boxes_path(move, room_id: empty_room.id)

      # The empty filtered result still offers the room chips to switch rooms.
      expect(response.body).to include("Kitchen").and include("Attic")
      expect(response.body).to include(I18n.t("boxes.empty.filtered_title"))
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

    it "highlights the new box and offers a View link after create (#336)" do
      post move_boxes_path(move), params: { box: { room_name: "Kitchen" } }
      follow_redirect!

      box = move.boxes.order(:created_at).last
      expect(response.body).to include("box-added-highlight")
      expect(response.body).to include(I18n.t("boxes.index.view_box"))
      expect(response.body).to include(move_box_path(move, box))
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

    it "shows a photo card with its item names as chips, and a placeholder card for a photo-less manual item" do
      box = create(:box, move:, number: "1")
      photo = create(:media, move:, box:)
      create(:item, move:, box:, source_media: photo, name: "Coffee maker")
      create(:item, :manual, move:, box:, name: "Reading glasses") # no source photo → placeholder card

      get move_box_path(move, box)

      aggregate_failures do
        expect(response.body).to include(I18n.t("boxes.contents.title"))
        expect(response.body).to include("Coffee maker") # chip inside the photo card
        # The manual item is its own placeholder card linking to the item detail.
        expect(response.body).to include("Reading glasses")
        expect(response.body).to include(I18n.t("boxes.contents.added_manually"))
      end
    end

    it "renders an item moved in from another box (foreign source photo) as its own card" do
      box = create(:box, move:, number: "1")
      other = create(:box, move:, number: "2")
      foreign_photo = create(:media, move:, box: other)
      # Items::Move keeps the original source_media_id (a photo in `other`), so the
      # item's source photo is not among this box's media — it must still show here.
      create(:item, move:, box:, source_media: foreign_photo, name: "Relocated drill")

      get move_box_path(move, box)

      expect(response.body).to include("Relocated drill")
      expect(response.body).not_to include(I18n.t("boxes.contents.empty_title"))
    end

    it "shows a review-state chip on an unreviewed standalone (manual) item card" do
      box = create(:box, move:, number: "1")
      create(:item, move:, box:, name: "Loose cable", review_state: "needs_correction") # manual, no photo

      get move_box_path(move, box)

      expect(response.body).to include(I18n.t("items.state.needs_correction"))
    end

    it "keeps an AI-generated item image out of the review walk (#416)" do
      box = create(:box, move:, number: "1")
      generated = create(:media, move:, box:, captured_via: "generated")
      create(:item, :manual, move:, box:, source_media: generated, name: "Brass lamp")

      get move_box_path(move, box)

      # The generated photo never had recognition, so it must not link into review
      # nor flip the box to a reviewed state.
      expect(response.body).not_to include(move_box_review_photo_path(move, box, media_id: generated.id))
      expect(response.body).not_to include(I18n.t("boxes.show.review_complete"))
    end

    it "renders a generated-image item through its own card linking to the item detail (#416)" do
      box = create(:box, move:, number: "1")
      generated = create(:media, move:, box:, captured_via: "generated")
      item = create(:item, :manual, move:, box:, source_media: generated, name: "Brass lamp")

      get move_box_path(move, box)

      # Not a gallery photo card — the item's own ItemCard, with a working detail link.
      expect(response.body).to include(Components::Boxes::ItemCard.dom_id(item))
      expect(response.body).to include(%(href="#{move_item_path(move, item)}"))
    end

    it "shows the generating state (no generate button) for an item with a fresh claim (#416)" do
      move.update!(image_provider: "fake") # image-ready, so the button would otherwise show
      box = create(:box, move:, number: "1")
      create(:item, :manual, move:, box:, name: "Lamp", image_generating_at: Time.current)

      get move_box_path(move, box)

      expect(response.body).to include(I18n.t("boxes.contents.generating"))
      expect(response.body).not_to include(I18n.t("boxes.contents.generate"))
    end

    it "gates the generate button by role via data-editable (one broadcast, role-safe) (#416)" do
      move.update!(image_provider: "fake")
      box = create(:box, move:, number: "1")
      create(:item, :manual, move:, box:, name: "Lamp")

      get move_box_path(move, box)

      # Editor: the surface is data-editable=true and the button rides in an
      # .editable-only wrapper (CSS shows it here, hides it for a read-only viewer).
      aggregate_failures do
        expect(response.body).to include('data-editable="true"')
        expect(response.body).to include("editable-only")
        expect(response.body).to include(I18n.t("boxes.contents.generate"))
      end
    end

    it "marks the box surface read-only for a viewer so CSS hides the generate button (#416)" do
      move.update!(image_provider: "fake")
      box = create(:box, move:, number: "1")
      create(:item, :manual, move:, box:, name: "Lamp")
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      get move_box_path(move, box)

      # data-editable=false → the .editable-only generate button is CSS-hidden, and
      # the route stays guarded by require_writable_move! regardless.
      expect(response.body).to include('data-editable="false"')
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

    it "badges a gallery photo whose every item is unpacked, but not one with an in-box item" do
      box = create(:box, move:, number: "1", status: "unpacking")
      all_unpacked = create(:media, move:, box:)
      create(:item, move:, box:, source_media: all_unpacked, presence_state: "removed")
      still_packed = create(:media, move:, box:)
      create(:item, move:, box:, source_media: still_packed, presence_state: "removed")
      create(:item, move:, box:, source_media: still_packed, presence_state: "in_box")

      get move_box_path(move, box)

      # The all-unpacked photo carries the badge; the one with a still-in-box item
      # does not (the gallery renders one badge → one occurrence).
      expect(response.body).to include(I18n.t("boxes.gallery.unpacked"))
      expect(response.body.scan(I18n.t("boxes.gallery.unpacked")).size).to eq(1)
    end

    it "shows no unpacked badge while the box is still packing" do
      box = create(:box, move:, number: "1", status: "packing")
      photo = create(:media, move:, box:)
      create(:item, move:, box:, source_media: photo, presence_state: "removed")

      get move_box_path(move, box)

      expect(response.body).not_to include(I18n.t("boxes.gallery.unpacked"))
    end

    it "does not badge a photo whose sourced item moved to another box and is still packed" do
      box = create(:box, move:, number: "1", status: "unpacking")
      other = create(:box, move:, number: "2")
      photo = create(:media, move:, box:)
      create(:item, move:, box:, source_media: photo, presence_state: "removed")
      # Sibling from the same photo moved out (box_id changes, source_media_id stays)
      # and is still in_box there — the photo is NOT fully unpacked.
      create(:item, move:, box: other, source_media: photo, presence_state: "in_box")

      get move_box_path(move, box)

      expect(response.body).not_to include(I18n.t("boxes.gallery.unpacked"))
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

  describe "DELETE /moves/:move_id/boxes/:id" do
    it "soft-deletes the box (cascading its items) and lands on the boxes home with a toast" do
      box = create(:box, move:, number: "1")
      create(:item, move:, box:, name: "Lamp")

      delete move_box_path(move, box)

      expect(response).to redirect_to(move_boxes_path(move))
      expect(flash[:notice]).to eq(I18n.t("boxes.destroy.deleted", number: box.number))
      expect(Box.find_by(id: box.id)).to be_nil           # gone from the default (kept) scope
      expect(Box.with_discarded.find(box.id)).to be_discarded
      expect(move.items.find_by(name: "Lamp")).to be_nil  # the item was discarded with it
    end

    it "is blocked for a viewer (403, box untouched)" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      box = create(:box, move:, number: "1")
      stub_current_user(viewer)

      delete move_box_path(move, box)

      expect(response).to have_http_status(:forbidden)
      expect(box.reload).not_to be_discarded
    end

    it "is blocked on an archived move (redirect, box untouched)" do
      archived = create(:move, :archived, created_by: user)
      box = create(:box, move: archived, number: "1")

      delete move_box_path(archived, box)

      expect(response).to redirect_to(move_boxes_path(archived))
      expect(box.reload).not_to be_discarded
    end
  end

  describe "PATCH /moves/:move_id/boxes/:id/fragile" do
    it "marks a box fragile and redirects to the box" do
      box = create(:box, :with_room, move:, number: "1", fragile: false)

      patch fragile_move_box_path(move, box), params: { fragile: true }

      expect(response).to redirect_to(move_box_path(move, box))
      expect(box.reload.fragile?).to be(true)
    end

    it "removes the fragile mark" do
      box = create(:box, :with_room, move:, number: "1", fragile: true)

      patch fragile_move_box_path(move, box), params: { fragile: false }

      expect(box.reload.fragile?).to be(false)
    end

    context "when responding as a Turbo Stream (no reload)" do
      it "streams the whole detail with the fragile chip and a toast" do
        box = create(:box, :with_room, move:, number: "1", fragile: false)

        patch fragile_move_box_path(move, box), params: { fragile: true }, as: :turbo_stream

        expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
        expect(response.body)
          .to include(%(action="replace" target="#{Views::Boxes::Show::ID}"))
          .and include(I18n.t("boxes.fragile_badge"))
          .and include(I18n.t("boxes.set_fragile.marked_fragile"))
        expect(box.reload.fragile?).to be(true)
      end
    end

    it "is blocked for a viewer (403, box untouched)" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      box = create(:box, :with_room, move:, number: "1", fragile: false)
      stub_current_user(viewer)

      patch fragile_move_box_path(move, box), params: { fragile: true }

      expect(response).to have_http_status(:forbidden)
      expect(box.reload.fragile?).to be(false)
    end

    it "is blocked on an archived move" do
      archived = create(:move, :archived, created_by: user)
      box = create(:box, :with_room, move: archived, number: "1", fragile: false)

      patch fragile_move_box_path(archived, box), params: { fragile: true }

      expect(response).to redirect_to(move_boxes_path(archived))
      expect(box.reload.fragile?).to be(false)
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

    context "when responding as a Turbo Stream (no reload)" do
      it "streams the whole detail in its new state with a toast on a plain seal" do
        box = create(:box, :with_room, move:, number: "1", status: "packing") # no items → plain seal

        patch transition_move_box_path(move, box), params: { to: "sealed" }, as: :turbo_stream

        expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
        expect(response.body)
          .to include(%(action="replace" target="#{Views::Boxes::Show::ID}"))
          .and include(I18n.t("boxes.status.sealed"))
          .and include(I18n.t("boxes.actions.unseal")) # the action set now offers Unseal
          .and include(I18n.t("boxes.transition.transitioned", status: I18n.t("boxes.status.sealed")))
        expect(box.reload.status).to eq("sealed")
      end

      it "streams the detail back to packing on an unseal" do
        box = create(:box, :with_room, move:, number: "1", status: "sealed")

        patch transition_move_box_path(move, box), params: { to: "packing" }, as: :turbo_stream

        expect(response.body)
          .to include(%(action="replace" target="#{Views::Boxes::Show::ID}"))
          .and include(I18n.t("boxes.status.packing"))
        expect(box.reload.status).to eq("packing")
      end

      it "refreshes the now-empty inventory when an unpacked transition cascades items out" do
        box = create(:box, :with_room, move:, number: "1", status: "unpacking")
        item = create(:item, move:, box:, name: "Sole sock", presence_state: "in_box")

        patch transition_move_box_path(move, box), params: { to: "unpacked" }, as: :turbo_stream

        expect(box.reload.status).to eq("unpacked")
        expect(item.reload.presence_state).to eq("removed") # cascade_unpacked
        # The streamed detail re-renders the inventory section as empty (the item is
        # no longer in-box) rather than leaving the stale list — the Codex #390 fix.
        expect(response.body)
          .to include(%(action="replace" target="#{Views::Boxes::Show::ID}"))
          .and include(I18n.t("boxes.contents.empty_title"))
      end

      it "streams an alert toast (no detail change) when a roomless seal is refused" do
        box = create(:box, move:, number: "1", status: "packing", room: nil)

        patch transition_move_box_path(move, box), params: { to: "sealed" }, as: :turbo_stream

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body)
          .to include(%(target="#{Components::FlashToasts::ID}"))
          .and include(I18n.t("boxes.transition.room_required"))
        expect(response.body).not_to include(%(action="replace" target="#{Views::Boxes::Show::ID}"))
        expect(box.reload.status).to eq("packing")
      end
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
      create(:item, move:, box:, name: "Mug")

      get seal_move_box_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("boxes.seal.title"))
      expect(response.body).to include("Mug") # deterministic suggestion (fake provider)
      # Regenerate opts out of Turbo prefetch so a hover can't spend AI quota.
      expect(response.body).to include('data-turbo-prefetch="false"')
    end

    it "is unprocessable for a box that cannot be sealed" do
      box = create(:box, :with_room, move:, number: "1", status: "in_transit")

      get seal_move_box_path(move, box)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is unprocessable (no AI spend) for a roomless box — the seal would fail room_required" do
      box = create(:box, move:, number: "1", status: "packing", room: nil)

      get seal_move_box_path(move, box)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /moves/:move_id/boxes/:id/description_suggestion" do
    it "returns the suggested description as JSON" do
      box = create(:box, :with_room, move:, number: "1", status: "packing")
      create(:item, move:, box:, name: "Novel")

      get description_suggestion_move_box_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["description"]).to eq("Novel")
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
