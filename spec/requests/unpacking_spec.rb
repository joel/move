require "rails_helper"

RSpec.describe "Unpacking" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/boxes/:box_id/unpacking" do
    it "renders the checklist for a box being unpacked" do
      box = create(:box, :with_room, move:, number: "7", status: "unpacking")
      create(:item, move:, box:, name: "Ceramic Plates", presence_state: "in_box")
      create(:item, move:, box:, name: "Coffee Maker", presence_state: "removed")

      get move_box_unpacking_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("unpacking.remaining_title"))
        .and include("Ceramic Plates").and include("Coffee Maker")
        .and include(I18n.t("unpacking.remaining_count", count: 1, total: 2))
    end

    it "puts the row's stable id on the button_to <form>, not the inner <button>" do
      # turbo_stream.remove(dom_id) must strip the whole row; if the id were on the
      # <button> the empty <form> would linger as a ghost gap (Codex P2).
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")

      get move_box_unpacking_path(move, box)

      dom_id = Components::Unpacking::ItemRow.dom_id(item, :remaining)
      expect(response.body).to match(/<form[^>]*\bid="#{dom_id}"/o)
      expect(response.body).not_to match(/<button[^>]*\bid="#{dom_id}"/o)
    end

    it "renders the celebration for an unpacked box" do
      box = create(:box, :with_room, move:, number: "8", status: "unpacked")

      get move_box_unpacking_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("unpacking.done_title"))
        .and include(I18n.t("unpacking.back_to_boxes"))
    end

    it "redirects to the box when it isn't being unpacked yet" do
      box = create(:box, :with_room, move:, status: "sealed")

      get move_box_unpacking_path(move, box)

      expect(response).to redirect_to(move_box_path(move, box))
    end
  end

  describe "PATCH .../unpacking/items/:item_id/remove" do
    it "marks the item removed and returns to the checklist" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  describe "PATCH .../unpacking/items/:item_id/restore" do
    it "restores a removed item to the box" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_restore_path(move, box, item)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(item.reload.presence_state).to eq("in_box")
    end

    it "refuses to restore on an already-unpacked box (no active checklist)" do
      box = create(:box, :with_room, move:, status: "unpacked")
      item = create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_restore_path(move, box, item)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  describe "PATCH .../unpacking/items/:item_id/remove on a non-unpacking box" do
    it "refuses to remove when the checklist isn't active" do
      box = create(:box, :with_room, move:, status: "in_transit")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(item.reload.presence_state).to eq("in_box")
    end
  end

  describe "PATCH .../remove as Turbo Stream (no reload)" do
    it "streams the row out, refreshes progress, and re-renders the unpacked section" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")
      create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body)
        .to include(%(action="remove" target="#{Components::Unpacking::ItemRow.dom_id(item, :remaining)}"))
        .and include(Components::Unpacking::ProgressCard::ID)
        .and include(Components::Unpacking::UnpackedSection::ID)
      expect(item.reload.presence_state).to eq("removed")
    end

    it "does not re-render the remaining section while items still remain" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")
      create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response.body)
        .not_to include(%(action="replace" target="#{Components::Unpacking::RemainingSection::ID}"))
      expect(response.body).not_to include(I18n.t("unpacking.all_clear_title"))
    end

    it "flips the remaining section to the all-clear empty state when the last item is removed" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response.body)
        .to include(%(action="replace" target="#{Components::Unpacking::RemainingSection::ID}"))
        .and include(I18n.t("unpacking.all_clear_title"))
    end
  end

  describe "PATCH .../restore as Turbo Stream (no reload)" do
    it "streams the row out and re-renders the remaining section at sorted position" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, name: "Lamp", presence_state: "removed")
      create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_restore_path(move, box, item), as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body)
        .to include(%(action="remove" target="#{Components::Unpacking::ItemRow.dom_id(item, :unpacked)}"))
        .and include(%(action="replace" target="#{Components::Unpacking::RemainingSection::ID}"))
        .and include("Lamp")
      expect(item.reload.presence_state).to eq("in_box")
    end

    it "hides the unpacked section when the last unpacked item is restored" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_restore_path(move, box, item), as: :turbo_stream

      expect(response.body)
        .to include(%(action="replace" target="#{Components::Unpacking::UnpackedSection::ID}"))
      # The re-rendered, now-empty unpacked section is hidden.
      expect(response.body).to match(/id="#{Components::Unpacking::UnpackedSection::ID}"[^>]*\bhidden\b/o)
    end
  end

  describe "PATCH .../unpacking/complete" do
    it "marks the box unpacked and cascades remaining items to removed" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_complete_path(move, box)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(box.reload.status).to eq("unpacked")
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  describe "PATCH .../unpacking/reopen" do
    it "reopens an unpacked box without restoring its items" do
      box = create(:box, :with_room, move:, status: "unpacked")
      item = create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_reopen_path(move, box)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(box.reload.status).to eq("unpacking")
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  describe "archived move (read-only)" do
    let(:move) { create(:move, created_by: user, status: "archived") }

    it "renders the checklist without remove forms" do
      box = create(:box, :with_room, move:, status: "unpacking")
      create(:item, move:, box:, presence_state: "in_box")

      get move_box_unpacking_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("unpacking.read_only"))
      expect(response.body).not_to include(move_box_unpacking_complete_path(move, box))
    end

    it "blocks marking the box unpacked" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_complete_path(move, box)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(box.reload.status).to eq("unpacking")
      expect(item.reload.presence_state).to eq("in_box")
    end
  end

  describe "PATCH .../unpacking/photos/:media_id/remove (#727)" do
    it "marks all the photo's still-in-box items removed and redirects to the box detail" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      plates = create(:item, move:, box:, source_media: photo, name: "Plates")
      mugs = create(:item, move:, box:, source_media: photo, name: "Mugs")
      moved = create(:item, move:, box: create(:box, move:), source_media: photo, name: "Kettle")

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id)

      expect(response).to redirect_to(move_box_path(move, box))
      aggregate_failures do
        expect(plates.reload.presence_state).to eq("removed")
        expect(mugs.reload.presence_state).to eq("removed")
        expect(moved.reload.presence_state).to eq("in_box")
      end
    end

    it "streams the photo card + contents header in place, never the checklist sections" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      create(:item, move:, box:, source_media: photo, name: "Plates")

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id), as: :turbo_stream

      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body)
        .to include(%(target="#{Components::Boxes::PhotoCard.dom_id(photo)}"))
        .and include(%(target="#{Components::Boxes::ContentsHeader::ID}"))
      expect(response.body).not_to include(Components::Unpacking::RemainingSection::ID)
      expect(response.body).not_to include(Components::Unpacking::ProgressCard::ID)
    end

    it "refuses outside an active unpacking checklist" do
      box = create(:box, :with_room, move:, status: "in_transit")
      photo = create(:media, move:, box:)
      item = create(:item, move:, box:, source_media: photo, name: "Plates")

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(item.reload.presence_state).to eq("in_box")
    end

    it "404s for a generated media id (never a photo card)" do
      box = create(:box, :with_room, move:, status: "unpacking")
      generated = create(:media, move:, box:, captured_via: "generated")

      patch move_box_unpacking_photo_remove_path(move, box, media_id: generated.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "origin=box toggles (#727 — B1 grid)" do
    it "streams the photo card + header for a photo item's remove, not the checklist" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      item = create(:item, move:, box:, source_media: photo, name: "Plates")

      patch move_box_unpacking_remove_path(move, box, item, params: { origin: "box" }), as: :turbo_stream

      expect(response.body)
        .to include(%(target="#{Components::Boxes::PhotoCard.dom_id(photo)}"))
        .and include(%(target="#{Components::Boxes::ContentsHeader::ID}"))
      expect(response.body).not_to include(Components::Unpacking::UnpackedSection::ID)
      expect(item.reload.presence_state).to eq("removed")
    end

    it "re-streams the review badge when a toggle changes the unreviewed count (Codex #728)" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      pending = create(:item, move:, box:, source_media: photo, name: "Plates", review_state: "pending_review")

      patch move_box_unpacking_remove_path(move, box, pending, params: { origin: "box" }), as: :turbo_stream

      expect(response.body)
        .to include(%(target="#{Components::BoxReviewBadge::ID}"))
        .and include(I18n.t("boxes.show.review_complete"))
    end

    it "streams the standalone item card for a manual item's restore" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, :manual, move:, box:, name: "Lamp", presence_state: "removed")

      patch move_box_unpacking_restore_path(move, box, item, params: { origin: "box" }), as: :turbo_stream

      expect(response.body)
        .to include(%(target="#{Components::Boxes::ItemCard.dom_id(item)}"))
        .and include(%(target="#{Components::Boxes::ContentsHeader::ID}"))
      expect(item.reload.presence_state).to eq("in_box")
    end

    it "falls back to a box-detail redirect for plain HTML" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, :manual, move:, box:, name: "Lamp")

      patch move_box_unpacking_remove_path(move, box, item, params: { origin: "box" })

      expect(response).to redirect_to(move_box_path(move, box))
    end

    it "keeps the checklist stream shape when no origin is sent" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")
      create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response.body).to include(Components::Unpacking::ProgressCard::ID)
      expect(response.body).not_to include(Components::Boxes::ContentsHeader::ID)
    end
  end
end
