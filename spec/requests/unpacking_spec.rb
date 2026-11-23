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

    # Removing the LAST item no longer streams the all-clear state — it
    # auto-completes the box and lands on the celebration (#755, below). The
    # all-clear remaining section is still reachable on a reopened box:
    it "renders the all-clear remaining state on a reopened box's checklist" do
      box = create(:box, :with_room, move:, status: "unpacking")
      create(:item, move:, box:, presence_state: "removed")

      get move_box_unpacking_path(move, box)

      expect(response.body).to include(I18n.t("unpacking.all_clear_title"))
    end
  end

  describe "last-item auto-complete (#755)" do
    it "completes the box and redirects to the celebration when the last checklist item is removed" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(box.reload.status).to eq("unpacked")

      follow_redirect!
      expect(response.body).to include(I18n.t("unpacking.done_title"))
    end

    it "completes and redirects to the box detail with a toast for the grid's last chip" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      item = create(:item, move:, box:, source_media: photo, name: "Plates")

      patch move_box_unpacking_remove_path(move, box, item, params: { origin: "box" }), as: :turbo_stream

      aggregate_failures do
        expect(response).to redirect_to(move_box_path(move, box))
        expect(flash[:notice]).to eq(I18n.t("unpacking.flash.completed"))
        expect(box.reload.status).to eq("unpacked")
      end
    end

    it "completes when the last photo is bulk-unpacked" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      create(:item, move:, box:, source_media: photo, name: "Plates")

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id), as: :turbo_stream

      aggregate_failures do
        expect(response).to redirect_to(move_box_path(move, box))
        expect(flash[:notice]).to eq(I18n.t("unpacking.flash.completed"))
        expect(box.reload.status).to eq("unpacked")
      end
    end

    it "self-heals: a replayed remove on an emptied-but-open box still completes it" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(box.reload.status).to eq("unpacked")
    end

    it "redirects even when a concurrent request already completed the box (race loser, #756 P2)" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")
      create(:item, move:, box:, presence_state: "in_box")
      # Simulate losing the completion race: the concurrent winner transitions
      # the box, so this request's CompleteIfEmpty (inside Items::Unpack)
      # re-reads `unpacked` and returns Success(nil) — the response must still
      # be the redirect, never checklist streams for a terminal box.
      loser = instance_double(Boxes::CompleteIfEmpty)
      allow(Boxes::CompleteIfEmpty).to receive(:new).and_return(loser)
      allow(loser).to receive(:call) do |box:, **|
        box.update!(status: "unpacked")
        Dry::Monads::Success(nil)
      end

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
    end

    it "redirects a restore that raced a completion instead of streaming success (#756 R3)" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "removed")
      create(:item, move:, box:, presence_state: "in_box")
      # The box completed between require_active_checklist and the box-locked
      # guard — the action refuses; success streams would strip a row the DB
      # still holds.
      raced = instance_double(Items::RestoreToBox)
      allow(Items::RestoreToBox).to receive(:new).and_return(raced)
      allow(raced).to receive(:call).and_return(Dry::Monads::Failure(:box_unpacked))

      patch move_box_unpacking_restore_path(move, box, item), as: :turbo_stream

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(item.reload.presence_state).to eq("removed")
    end

    it "leaves the box unpacking while other items remain (streams as before)" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")
      create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(box.reload.status).to eq("unpacking")
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
      create(:item, :manual, move:, box:, name: "Lamp") # more remain — no auto-complete (#755)

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

  describe "refused toggles (#729)" do
    # The action refuses after the controller's guards passed (a phase race
    # between require_active_checklist and the action's own guard). Stubbed:
    # the race window is not reproducible in a request spec.
    def refuse(action_class, reason = :wrong_phase)
      refused = instance_double(action_class)
      allow(action_class).to receive(:new).and_return(refused)
      allow(refused).to receive(:call).and_return(Dry::Monads::Failure(reason))
    end

    let(:checklist_regions) do
      [Components::Unpacking::ProgressCard::ID, Components::Unpacking::RemainingSection::ID,
       Components::Unpacking::UnpackedSection::ID]
    end

    it "re-streams the checklist's real state with an alert when a remove is refused" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box", name: "Plates")
      create(:item, move:, box:, presence_state: "removed")
      refuse(Items::Unpack)

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      body = response.body
      aggregate_failures do
        # Every region re-rendered from the DB, morphed (focus + scroll kept).
        checklist_regions.each do |id|
          expect(body).to match(/<turbo-stream (?=[^>]*action="replace")(?=[^>]*method="morph")[^>]*target="#{id}"/)
        end
        # The tapped row is still in Remaining — never streamed out.
        expect(body).not_to include(%(action="remove"))
        expect(body).to include(Components::Unpacking::ItemRow.dom_id(item, :remaining))
        expect(body).to include(ERB::Util.h(I18n.t("unpacking.flash.remove_failed", name: "Plates")))
        expect(body).not_to include(ERB::Util.h(I18n.t("unpacking.flash.completed")))
      end
      expect(item.reload.presence_state).to eq("in_box")
    end

    it "re-streams the grid card with an alert for a refused origin=box remove" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      item = create(:item, move:, box:, source_media: photo, name: "Plates")
      refuse(Items::Unpack)

      patch move_box_unpacking_remove_path(move, box, item, params: { origin: "box" }), as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body)
        .to include(%(target="#{Components::Boxes::PhotoCard.dom_id(photo)}"))
        .and include(ERB::Util.h(I18n.t("unpacking.flash.remove_failed", name: "Plates")))
      expect(response.body).not_to include(Components::Unpacking::UnpackedSection::ID)
    end

    it "redirects a refused HTML remove back to the checklist with the alert" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box", name: "Plates")
      refuse(Items::Unpack)

      patch move_box_unpacking_remove_path(move, box, item)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(flash[:alert]).to eq(I18n.t("unpacking.flash.remove_failed", name: "Plates"))
    end

    it "re-streams the photo card with an alert when a photo unpack is refused" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      item = create(:item, move:, box:, source_media: photo, name: "Plates")
      refuse(Items::MarkPhotoRemoved)

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id), as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body)
        .to include(%(target="#{Components::Boxes::PhotoCard.dom_id(photo)}"))
        .and include(%(target="#{Components::Boxes::ContentsHeader::ID}"))
        .and include(ERB::Util.h(I18n.t("unpacking.flash.photo_remove_failed")))
      expect(response.body).not_to include(ERB::Util.h(I18n.t("unpacking.flash.completed")))
      expect(item.reload.presence_state).to eq("in_box")
    end

    it "drops the card when the photo left the box before the action ran (Failure(:not_found))" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      plates = create(:item, move:, box:, source_media: photo, name: "Plates")
      # A Photos::Move (photo + its in-box item) commits before the action runs.
      elsewhere = create(:box, :with_room, move:, status: "unpacking")
      refused = instance_double(Items::MarkPhotoRemoved)
      allow(Items::MarkPhotoRemoved).to receive(:new).and_return(refused)
      allow(refused).to receive(:call) do
        [photo, plates].each { |record| record.update!(box: elsewhere) }
        Dry::Monads::Failure(:not_found)
      end

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id), as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body)
        .to include(%(action="remove" target="#{Components::Boxes::PhotoCard.dom_id(photo)}"))
        .and include(ERB::Util.h(I18n.t("unpacking.flash.photo_gone")))
    end

    it "redirects a refused HTML photo unpack to the box detail with the alert" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      refuse(Items::MarkPhotoRemoved)

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id)

      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:alert]).to eq(I18n.t("unpacking.flash.photo_remove_failed"))
    end
  end

  describe "renders from post-action state after a concurrent change (#877)" do
    # A concurrent writer commits after the controller loaded @box/@item/@media
    # and before (or during) the action: the response must describe the DB,
    # never the request's pre-action objects.

    # The action refuses after `concurrently` committed (the stubbed refusal
    # stands in for the guard that tripped on the concurrent change).
    def refuse_after(action_class, reason = :wrong_phase)
      refused = instance_double(action_class)
      allow(action_class).to receive(:new).and_return(refused)
      allow(refused).to receive(:call) do
        yield
        Dry::Monads::Failure(reason)
      end
    end

    # A real Photos::Move lands right after action_class's first call returns.
    def standalone_update
      %(action="update" target="#{Components::Boxes::ContentsGrid::STANDALONE_ID}")
    end

    # The ItemCard root ids in document order.
    def item_card_ids(html)
      Nokogiri::HTML(html).css("[id]").pluck("id").grep(/\Abox_item_.+_card\z/)
    end

    def move_photo_after_first_call(action_class, photo, destination)
      moved = false
      allow(action_class).to receive(:new).and_wrap_original do |original|
        original.call.tap do |action|
          allow(action).to receive(:call).and_wrap_original do |call, **kw|
            call.call(**kw).tap do
              next if moved

              moved = true
              Photos::Move.new.call(media: Media.find(photo.id), target_box: Box.find(destination.id), mover: user)
            end
          end
        end
      end
    end

    it "drops the photo card with a toast when the photo moves away mid-loop" do
      box = create(:box, :with_room, move:, status: "unpacking")
      destination = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      plates = create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")
      mugs = create(:item, :confirmed, move:, box:, source_media: photo, name: "Mugs")
      create(:item, :confirmed, move:, box:, name: "Lamp") # keeps the box open
      move_photo_after_first_call(Items::MarkRemoved, photo, destination)

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id), as: :turbo_stream

      # Plates was unpacked before the move and stays behind: the photo card
      # goes and the standalone region is redrawn with it (Codex #886, #889).
      card = Components::Boxes::PhotoCard.dom_id(photo)
      expect(response.body)
        .to include(%(action="remove" target="#{card}"), standalone_update, Components::Boxes::ItemCard.dom_id(plates),
                    %(target="#{Components::Boxes::ContentsHeader::ID}"),
                    ERB::Util.h(I18n.t("unpacking.flash.photo_moved")))
      expect(response.body).not_to include(Components::Boxes::ItemCard.dom_id(mugs))
      expect([plates.reload.presence_state, mugs.reload.box_id]).to eq(["removed", destination.id])
    end

    it "redirects a moved-away HTML photo unpack to the box detail with the notice" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      create(:item, :confirmed, move:, box:, name: "Lamp")
      moved = instance_double(Items::MarkPhotoRemoved)
      allow(Items::MarkPhotoRemoved).to receive(:new).and_return(moved)
      allow(moved).to receive(:call)
        .and_return(Dry::Monads::Success(items: [], completed_box: nil, photo_moved: true))

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id)

      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:notice]).to eq(I18n.t("unpacking.flash.photo_moved"))
    end

    it "drops the photo card when a refused photo unpack follows a concurrent move" do
      box = create(:box, :with_room, move:, status: "unpacking")
      destination = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      create(:item, :confirmed, move:, box:, name: "Lamp")
      refuse_after(Items::MarkPhotoRemoved) { photo.update!(box: destination) }

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id), as: :turbo_stream

      card = Components::Boxes::PhotoCard.dom_id(photo)
      expect(response.body).to include(%(action="remove" target="#{card}"))
      # Nothing was left behind, so the standalone region is untouched (#889).
      expect(response.body).not_to include(%(action="replace" target="#{card}"), standalone_update)
    end

    it "turns a chip into a standalone card when its photo moves away after the unpack (Codex #886)" do
      box = create(:box, :with_room, move:, status: "unpacking")
      destination = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      plates = create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")
      mugs = create(:item, :confirmed, move:, box:, source_media: photo, name: "Mugs")
      create(:item, :manual, move:, box:, name: "Lamp") # keeps the box open
      # Plates is unpacked, then a Photos::Move takes the photo and Mugs (in_box).
      move_photo_after_first_call(Items::Unpack, photo, destination)

      patch move_box_unpacking_remove_path(move, box, plates, params: { origin: "box" }), as: :turbo_stream

      card = Components::Boxes::PhotoCard.dom_id(photo)
      expect(response.body)
        .to include(%(action="remove" target="#{card}"), standalone_update, Components::Boxes::ItemCard.dom_id(plates))
      expect(response.body).not_to include(Components::Boxes::ItemCard.dom_id(mugs), %(action="replace" target="#{card}"))
    end

    it "places the left-behind cards where a full grid render would (#889)" do
      box = create(:box, :with_room, move:, status: "unpacking")
      destination = create(:box, :with_room, move:, status: "unpacking")
      older_photo = create(:media, move:, box:, created_at: 2.days.ago)
      create(:item, :confirmed, move:, box:, source_media: older_photo, name: "Books")
      # The newer photo leads the grid, so its card is not the last photo card.
      photo = create(:media, move:, box:, created_at: 1.day.ago)
      plates = create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates", created_at: 2.hours.ago)
      lamp = create(:item, :manual, move:, box:, name: "Lamp", created_at: 3.hours.ago)
      vase = create(:item, :manual, move:, box:, name: "Vase", created_at: 1.hour.ago)
      move_photo_after_first_call(Items::Unpack, photo, destination)

      patch move_box_unpacking_remove_path(move, box, plates, params: { origin: "box" }), as: :turbo_stream

      streamed = item_card_ids(Nokogiri::HTML5.fragment(response.body)
        .at_css(%(turbo-stream[action="update"][target="#{Components::Boxes::ContentsGrid::STANDALONE_ID}"]))
        .at_css("template").inner_html)
      get move_box_path(move, box)
      rendered = item_card_ids(response.parsed_body
        .at_css("##{Components::Boxes::ContentsGrid::STANDALONE_ID}").to_html)

      expect(streamed).to eq([vase, plates, lamp].map { |item| Components::Boxes::ItemCard.dom_id(item) })
      expect(streamed).to eq(rendered)
    end

    it "redirects a refused photo unpack whose concurrent move completed the box (Codex #886 R2)" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      plates = create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")
      create(:item, :confirmed, move:, box:, source_media: photo, name: "Mugs", presence_state: "removed")
      # The move takes the photo + Plates (its last in-box item) and completes
      # the source box before the action's ownership check refuses.
      refuse_after(Items::MarkPhotoRemoved, :not_found) do
        Photos::Move.new.call(media: Media.find(photo.id), target_box: create(:box, :with_room, move:), mover: user)
      end

      patch move_box_unpacking_photo_remove_path(move, box, media_id: photo.id), as: :turbo_stream

      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:notice]).to eq(I18n.t("unpacking.flash.completed"))
      expect([box.reload.status, plates.reload.box_id]).not_to include("unpacking", box.id)
    end

    it "redraws a refused standalone card from the DB, not the pre-action item" do
      box = create(:box, :with_room, move:, status: "unpacking")
      lamp = create(:item, :manual, move:, box:, name: "Lamp")
      create(:item, :manual, move:, box:, name: "Fan") # keeps the box open
      # Another tab unpacked the lamp after set_item loaded it in_box.
      refuse_after(Items::Unpack) { lamp.update!(presence_state: "removed") }

      patch move_box_unpacking_remove_path(move, box, lamp, params: { origin: "box" }), as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      body = response.body
      aggregate_failures do
        expect(body).to include(%(target="#{Components::Boxes::ItemCard.dom_id(lamp)}"))
        # The card's control matches the DB (Restore), not the stale Unpack.
        expect(body).to include(move_box_unpacking_restore_path(move, box, lamp))
        expect(body).not_to include(move_box_unpacking_remove_path(move, box, lamp))
      end
    end

    it "drops a refused standalone card when the item left the box concurrently" do
      box = create(:box, :with_room, move:, status: "unpacking")
      lamp = create(:item, :manual, move:, box:, name: "Lamp")
      create(:item, :manual, move:, box:, name: "Fan")
      elsewhere = create(:box, :with_room, move:, status: "unpacking")
      refuse_after(Items::Unpack) { lamp.update!(box: elsewhere) }

      patch move_box_unpacking_remove_path(move, box, lamp, params: { origin: "box" }), as: :turbo_stream

      card = Components::Boxes::ItemCard.dom_id(lamp)
      expect(response.body).to include(%(action="remove" target="#{card}"))
      expect(response.body).not_to include(%(action="replace" target="#{card}"))
    end

    it "redirects a refused grid remove to the box's current phase when the box completed concurrently" do
      box = create(:box, :with_room, move:, status: "unpacking")
      lamp = create(:item, :manual, move:, box:, name: "Lamp")
      refuse_after(Items::Unpack) do
        lamp.update!(presence_state: "removed")
        box.update!(status: "unpacked")
      end

      patch move_box_unpacking_remove_path(move, box, lamp, params: { origin: "box" }), as: :turbo_stream

      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:notice]).to eq(I18n.t("unpacking.flash.completed"))
    end

    it "redirects a refused checklist remove to the celebration when the box completed concurrently" do
      box = create(:box, :with_room, move:, status: "unpacking")
      lamp = create(:item, move:, box:, name: "Lamp")
      refuse_after(Items::Unpack) do
        lamp.update!(presence_state: "removed")
        box.update!(status: "unpacked")
      end

      patch move_box_unpacking_remove_path(move, box, lamp), as: :turbo_stream

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
    end
  end

  describe "origin=box toggles (#727 — B1 grid)" do
    it "streams the photo card + header for a photo item's remove, not the checklist" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      item = create(:item, move:, box:, source_media: photo, name: "Plates")
      create(:item, move:, box:, source_media: photo, name: "Mugs") # more remain — no auto-complete (#755)

      patch move_box_unpacking_remove_path(move, box, item, params: { origin: "box" }), as: :turbo_stream

      expect(response.body)
        .to include(%(target="#{Components::Boxes::PhotoCard.dom_id(photo)}"))
        .and include(%(target="#{Components::Boxes::ContentsHeader::ID}"))
      # The card replace morphs so a keyboard user's focus survives the toggle.
      expect(response.body).to include(%(method="morph"))
      expect(response.body).not_to include(Components::Unpacking::UnpackedSection::ID)
      expect(item.reload.presence_state).to eq("removed")
    end

    it "re-streams the review badge when a toggle changes the unreviewed count (Codex #728)" do
      box = create(:box, :with_room, move:, status: "unpacking")
      photo = create(:media, move:, box:)
      pending = create(:item, move:, box:, source_media: photo, name: "Plates", review_state: "pending_review")
      # Confirmed (the factory default is pending_review, which would keep the
      # badge pending) — present only so the box doesn't auto-complete (#755).
      create(:item, move:, box:, source_media: photo, name: "Mugs", review_state: "confirmed")

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
      create(:item, :manual, move:, box:, name: "Fan") # more remain — no auto-complete (#755)

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
