# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Per-photo review" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  def detected(name:, **attrs)
    create(:item, move:, box:, source_media: media, name:, review_state: "pending_review", **attrs)
  end

  describe "GET .../review (entry)" do
    it "enters the walk at the first photo with items" do
      detected(name: "Lamp")

      get move_box_review_path(move, box)

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
    end

    it "resumes at the first photo that still has unreviewed items" do
      done = create(:media, move:, box:, captured_at: 2.hours.ago)
      create(:item, move:, box:, source_media: done, name: "Sofa", review_state: "confirmed")
      pending_photo = media # captured now (after `done`)
      detected(name: "Lamp")

      get move_box_review_path(move, box)

      expect(response).to redirect_to(move_box_review_photo_path(move, box, pending_photo))
    end

    it "redirects back to the box when there is nothing to review" do
      get move_box_review_path(move, box)

      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:notice]).to eq(I18n.t("reviews.flash.nothing"))
    end
  end

  describe "GET .../review/photo/:media_id" do
    it "lists every item from the photo with progress" do
      detected(name: "Coffee machine")
      detected(name: "Fruit bowl")

      get move_box_review_photo_path(move, box, media)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Coffee machine").and include("Fruit bowl")
      expect(response.body).to include(I18n.t("reviews.photo.progress", position: 1, total: 1))
      # The add-form clears + refocuses after a streamed add (Turbo doesn't reset a
      # stream-responding form) — keep that wiring so rapid entry stays usable.
      expect(response.body).to include("reset-form")
      # Rows swipe-reveal their Edit/Remove options below lg (Ui::SwipeActions).
      expect(response.body).to include("swipe-actions")
    end

    # #660 — reviewing is explicit: a plain GET (or a hover prefetch) never mutates.
    it "does not change review state when shown" do
      pending_item = detected(name: "Chair")
      needs = detected(name: "Desk", review_state: "needs_correction")

      get move_box_review_photo_path(move, box, media)

      expect(pending_item.reload.review_state).to eq("pending_review")
      expect(needs.reload.review_state).to eq("needs_correction")
    end

    it "offers Mark as Reviewed and an Ignore link to the next photo when more remain" do
      detected(name: "Lamp")
      other = create(:media, move:, box:)
      create(:item, move:, box:, source_media: other, name: "Sofa", review_state: "pending_review")

      get move_box_review_photo_path(move, box, media)

      expect(response.body).to include(move_box_review_photo_path(move, box, other))
      expect(response.body).to include(I18n.t("reviews.photo.mark_reviewed"))
      expect(response.body).to include(I18n.t("reviews.photo.ignore"))
    end

    it "falls back to the plain navigation label when the photo has nothing pending" do
      detected(name: "Lamp", review_state: "confirmed")
      other = create(:media, move:, box:)
      create(:item, move:, box:, source_media: other, name: "Sofa", review_state: "pending_review")

      get move_box_review_photo_path(move, box, media)

      expect(response.body).to include(I18n.t("reviews.photo.next"))
      expect(response.body).not_to include(I18n.t("reviews.photo.mark_reviewed"))
    end
  end

  # #660 — the explicit confirm: POST marks this photo's unreviewed items and
  # advances the walk (queue mode crosses boxes).
  describe "POST .../review/photo/:media_id/mark_reviewed" do
    it "confirms the photo's unreviewed items and advances to the next photo" do
      pending_item = detected(name: "Chair")
      needs = detected(name: "Desk", review_state: "needs_correction")
      other = create(:media, move:, box:)
      create(:item, move:, box:, source_media: other, name: "Sofa", review_state: "pending_review")

      post move_box_review_mark_reviewed_path(move, box, media)

      aggregate_failures do
        expect(pending_item.reload.review_state).to eq("confirmed")
        expect(needs.reload.review_state).to eq("confirmed")
        expect(response).to redirect_to(move_box_review_photo_path(move, box, other))
        expect(flash[:notice]).to eq(I18n.t("reviews.flash.photo_marked"))
      end
    end

    it "finishes at the box page after the last photo" do
      detected(name: "Chair")

      post move_box_review_mark_reviewed_path(move, box, media)

      expect(response).to redirect_to(move_box_path(move, box))
    end

    it "advances cross-box with the queue param in queue mode" do
      item = detected(name: "Lamp")
      other_box = create(:box, move:, number: "42")
      newer = create(:media, move:, box: other_box, captured_at: 1.hour.from_now)
      create(:item, move:, box: other_box, source_media: newer, review_state: "pending_review")

      post move_box_review_mark_reviewed_path(move, box, media, queue: "move")

      expect(item.reload.review_state).to eq("confirmed")
      expect(response).to redirect_to(move_box_review_photo_path(move, other_box, newer, queue: "move"))
    end

    it "finishes at the queue page after the last pending photo in queue mode" do
      detected(name: "Lamp")

      post move_box_review_mark_reviewed_path(move, box, media, queue: "move")

      expect(response).to redirect_to(move_review_path(move))
    end

    it "returns 404 for a photo in another box" do
      other_box = create(:box, move:, number: "42")
      foreign = create(:media, move:, box: other_box)

      post move_box_review_mark_reviewed_path(move, box, foreign)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH .../rename" do
    it "renames the item and answers 204 (no navigation)" do
      item = detected(name: "Cofee machine")

      patch move_box_review_rename_item_path(move, box, media, item), params: { name: "Coffee machine" }

      expect(response).to have_http_status(:no_content)
      expect(item.reload.name).to eq("Coffee machine")
    end

    it "answers 422 and keeps the name when the new name is blank (#147)" do
      item = detected(name: "Lamp")

      patch move_box_review_rename_item_path(move, box, media, item), params: { name: "" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(item.reload.name).to eq("Lamp")
    end
  end

  describe "PATCH .../remove" do
    it "removes the item from the box and returns to the photo" do
      item = detected(name: "Glass backsplash")

      patch move_box_review_remove_item_path(move, box, media, item)

      expect(item.reload.presence_state).to eq("removed")
      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
    end

    it "keeps an emptied photo in the walk so later photos can't be skipped" do
      only_item = detected(name: "Lone detection")
      later = create(:media, move:, box:, captured_at: 1.hour.from_now)
      create(:item, move:, box:, source_media: later, name: "Sofa", review_state: "pending_review")

      patch move_box_review_remove_item_path(move, box, media, only_item)
      follow_redirect!

      # Back on the now-empty photo 1, still "Photo 1 of 2" with Next → the later
      # photo (not a premature "Finish").
      expect(response.body).to include(I18n.t("reviews.photo.progress", position: 1, total: 2))
      expect(response.body).to include(move_box_review_photo_path(move, box, later))
    end
  end

  describe "POST .../items (add a missed item)" do
    it "creates a confirmed manual item tied to the photo" do
      expect do
        post move_box_review_add_item_path(move, box, media), params: { item: { name: "Kettle" } }
      end.to change(box.items, :count).by(1)

      item = box.items.find_by(name: "Kettle")
      expect(item).to have_attributes(created_via: "manual", review_state: "confirmed", source_media_id: media.id)
      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
    end

    it "re-shows the photo with an alert when the name is blank" do
      post move_box_review_add_item_path(move, box, media), params: { item: { name: "" } }

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
      expect(flash[:alert]).to eq(I18n.t("reviews.flash.add_failed"))
    end
  end

  describe "PATCH .../remove as Turbo Stream (no reload)" do
    it "streams the row out without re-rendering the rest of the list" do
      item = detected(name: "Glass backsplash")
      detected(name: "Stays put")

      patch move_box_review_remove_item_path(move, box, media, item), as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body)
        .to include(%(action="remove" target="#{Components::Reviews::ItemRow.dom_id(item)}"))
      expect(response.body).not_to include(%(target="#{Components::Reviews::ItemList::ID}"))
      expect(item.reload.presence_state).to eq("removed")
    end

    it "flips the list to the empty state when the last item is removed" do
      only_item = detected(name: "Lone detection")

      patch move_box_review_remove_item_path(move, box, media, only_item), as: :turbo_stream

      expect(response.body)
        .to include(%(action="replace" target="#{Components::Reviews::ItemList::ID}"))
        .and include(I18n.t("reviews.photo.empty_title"))
    end
  end

  describe "POST .../items as Turbo Stream (no reload)" do
    it "replaces the list with the highlighted new row and a confirmation toast" do
      detected(name: "Existing")

      post move_box_review_add_item_path(move, box, media),
           params: { item: { name: "Kettle" } }, as: :turbo_stream

      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      item = box.items.find_by(name: "Kettle")
      # Always replace the stable list wrapper (never append to a maybe-absent rows
      # container) so a new row never gets silently dropped on a stale/empty client.
      expect(response.body)
        .to include(%(action="replace" target="#{Components::Reviews::ItemList::ID}"))
        .and include(Components::Reviews::ItemRow.dom_id(item))
        .and include("highlight")
        .and include("Existing")
        .and include(I18n.t("reviews.flash.item_added", name: "Kettle"))
    end

    it "replaces the empty list when adding the first item to a bare photo" do
      post move_box_review_add_item_path(move, box, media),
           params: { item: { name: "First" } }, as: :turbo_stream

      expect(response.body)
        .to include(%(action="replace" target="#{Components::Reviews::ItemList::ID}"))
        .and include("First")
    end

    it "streams an alert toast (no row) when the name is blank" do
      post move_box_review_add_item_path(move, box, media),
           params: { item: { name: "" } }, as: :turbo_stream

      expect(response.body)
        .to include(%(target="#{Components::FlashToasts::ID}"))
        .and include(I18n.t("reviews.flash.add_failed"))
      expect(response.body).not_to include(%(target="#{Components::Reviews::ItemList::ROWS_ID}"))
    end
  end

  describe "PATCH .../review/photo/:media_id/move (#317)" do
    it "renders the move control on the photo page when another box exists" do
      detected(name: "Lamp")
      create(:box, move:, number: "7")

      get move_box_review_photo_path(move, box, media)

      expect(response.body).to include(I18n.t("reviews.photo.move_heading"))
    end

    it "moves the photo and its items to the target box and redirects there" do
      item = detected(name: "Lamp")
      target = create(:box, move:, number: "7")

      patch move_box_review_move_photo_path(move, box, media), params: { target_box_id: target.id }

      expect(media.reload.box_id).to eq(target.id)
      expect(item.reload.box_id).to eq(target.id)
      expect(response).to redirect_to(move_box_path(move, target))
      expect(flash[:notice]).to eq(I18n.t("reviews.flash.photo_moved", number: target.number))
    end

    it "rejects a target outside this Move (scoped to @move.boxes) without moving the photo" do
      detected(name: "Lamp")
      foreign = create(:box, move: create(:move)) # another Move → not found in @move.boxes

      patch move_box_review_move_photo_path(move, box, media), params: { target_box_id: foreign.id }

      expect(media.reload.box_id).to eq(box.id)
      # The cross-Move box id resolves to nil under @move.boxes, so it's :box_missing.
      expect(flash[:alert]).to eq(I18n.t("reviews.flash.move_photo_errors.box_missing"))
    end
  end

  describe "archived Move (read-only)" do
    let(:move) { create(:move, :archived, created_by: user) }

    it "shows the photo read-only without confirming items" do
      item = detected(name: "Lamp")

      get move_box_review_photo_path(move, box, media)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("reviews.photo.view_only"))
      expect(item.reload.review_state).to eq("pending_review")
    end

    it "refuses a rename and redirects with the archived alert" do
      item = detected(name: "Lamp")

      patch move_box_review_rename_item_path(move, box, media, item), params: { name: "Desk lamp" }

      expect(item.reload.name).to eq("Lamp")
      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:alert]).to eq(I18n.t("moves.archived_alert"))
    end

    it "refuses mark_reviewed and keeps the items pending" do
      item = detected(name: "Lamp")

      post move_box_review_mark_reviewed_path(move, box, media)

      expect(item.reload.review_state).to eq("pending_review")
      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:alert]).to eq(I18n.t("moves.archived_alert"))
    end
  end

  describe "DELETE .../review/photo/:media_id (delete photo)" do
    it "deletes the photo and its items and redirects to the box" do
      item = detected(name: "Lamp")

      delete move_box_review_photo_path(move, box, media)

      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:notice]).to eq(I18n.t("reviews.flash.photo_deleted"))
      expect(Media.kept.exists?(media.id)).to be(false)
      expect(Item.kept.exists?(item.id)).to be(false)
    end

    it "refuses on a sealed box (packing only) and keeps the photo" do
      sealed = create(:box, :sealed, move:)
      photo = create(:media, move:, box: sealed)

      delete move_box_review_photo_path(move, sealed, photo)

      expect(response).to redirect_to(move_box_review_photo_path(move, sealed, photo))
      expect(flash[:alert]).to eq(I18n.t("reviews.flash.photo_delete_wrong_phase"))
      expect(Media.kept.exists?(photo.id)).to be(true)
    end
  end

  describe "POST .../review/photo/:media_id/retake (retake photo)" do
    def upload
      Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/sample_image.png"), "image/png")
    end

    it "replaces the image, clears image_unavailable, and redirects back" do
      media.update!(image_unavailable: true)

      post move_box_review_retake_photo_path(move, box, media), params: { file: upload }

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
      expect(flash[:notice]).to eq(I18n.t("reviews.flash.photo_retaken"))
      expect(media.reload.image_unavailable?).to be(false)
    end

    it "surfaces a friendly error when no file is chosen" do
      post move_box_review_retake_photo_path(move, box, media)

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
      expect(flash[:alert]).to eq(I18n.t("reviews.flash.retake_errors.no_file"))
    end
  end

  describe "queue mode (?queue=move) — the Move-wide walk (#654)" do
    def pending_photo(box:, captured_at:)
      photo = create(:media, move:, box:, captured_at:)
      create(:item, move:, box:, source_media: photo, review_state: "pending_review")
      photo
    end

    it "advances across box boundaries to the oldest remaining pending photo" do
      detected(name: "Lamp") # in `box`, on `media` (captured now)
      other_box = create(:box, move:, number: "42")
      newer = pending_photo(box: other_box, captured_at: 1.hour.from_now)

      get move_box_review_photo_path(move, box, media, queue: "move")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(move_box_review_photo_path(move, other_box, newer, queue: "move"))
      expect(response.body).to include(I18n.t("reviews.photo.queue_progress", count: 1))
    end

    it "links the location badge to the photo's box (#684 — the back arrow exits to the queue)" do
      detected(name: "Lamp")

      get move_box_review_photo_path(move, box, media, queue: "move")

      aggregate_failures do
        expect(response.body).to include(
          %(aria-label="#{I18n.t("reviews.photo.view_box", number: box.number)}")
        )
        # The badge anchor carries the box href (the queue-mode box jump).
        expect(response.body).to include(%(href="#{move_box_path(move, box)}"))
      end
    end

    it "keeps the box-mode badge a plain locator (the back arrow already links the box)" do
      detected(name: "Lamp")

      get move_box_review_photo_path(move, box, media)

      expect(response.body).not_to include(I18n.t("reviews.photo.view_box", number: box.number))
    end

    it "locates the photo with a Box badge and exits to the queue from the last photo" do
      detected(name: "Lamp")

      get move_box_review_photo_path(move, box, media, queue: "move")

      aggregate_failures do
        expect(response.body).to include(I18n.t("reviews.photo.queue_badge", number: box.number))
        expect(response.body).to include(I18n.t("reviews.photo.queue_progress.zero"))
        # The pending photo renders the Mark/Ignore pair; both exit to the queue.
        expect(response.body).to include(I18n.t("reviews.photo.mark_reviewed"))
        expect(response.body).to include(I18n.t("reviews.photo.ignore"))
        expect(response.body).to include(move_review_path(move))
      end
    end

    it "does not change review state on open in queue mode either (#660)" do
      item = detected(name: "Lamp")

      get move_box_review_photo_path(move, box, media, queue: "move")

      expect(item.reload.review_state).to eq("pending_review")
    end

    it "does not activate on any other queue value" do
      detected(name: "Lamp")

      get move_box_review_photo_path(move, box, media, queue: "bogus")

      expect(response.body).to include(I18n.t("reviews.photo.progress", position: 1, total: 1))
    end

    it "advances strictly forward on a read-only Move (no ping-pong, and it terminates)" do
      archived = create(:move, :archived, created_by: user)
      archived_box = create(:box, move: archived)
      photos = [2.hours.ago, 1.hour.ago, Time.current].map do |at|
        photo = create(:media, move: archived, box: archived_box, captured_at: at)
        create(:item, move: archived, box: archived_box, source_media: photo, review_state: "pending_review")
        photo
      end

      # Nothing is confirmed on a read-only Move, so from the middle photo the
      # walk must offer the NEXT one (never back to the oldest)...
      get move_box_review_photo_path(archived, archived_box, photos[1], queue: "move")
      expect(response.body).to include(move_box_review_photo_path(archived, archived_box, photos[2], queue: "move"))
      expect(response.body).not_to include(">#{move_box_review_photo_path(archived, archived_box, photos[0])}?queue")

      # ...and from the newest, finish back to the queue.
      get move_box_review_photo_path(archived, archived_box, photos[2], queue: "move")
      expect(response.body).to include(I18n.t("reviews.photo.finish"))
      expect(response.body).to include(move_review_path(archived))
    end

    it "threads the queue through the add-item HTML fallback" do
      detected(name: "Lamp")

      post move_box_review_add_item_path(move, box, media, queue: "move"), params: { item: { name: "Mug" } }

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media, queue: "move"))
    end

    it "threads the queue through the remove-item HTML fallback" do
      item = detected(name: "Lamp")

      patch move_box_review_remove_item_path(move, box, media, item, queue: "move")

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media, queue: "move"))
    end

    it "stays in the walk after moving the photo to another box" do
      detected(name: "Lamp")
      target = create(:box, move:, number: "9")

      patch move_box_review_move_photo_path(move, box, media, queue: "move"),
            params: { target_box_id: target.id }

      expect(response).to redirect_to(move_box_review_photo_path(move, target, media, queue: "move"))
    end

    it "returns to the queue after deleting the photo" do
      detected(name: "Lamp")

      delete move_box_review_photo_path(move, box, media, queue: "move")

      expect(response).to redirect_to(move_review_path(move))
    end

    it "threads the queue through the retake redirect" do
      file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/sample_image.png"), "image/png")

      post move_box_review_retake_photo_path(move, box, media, queue: "move"), params: { file: }

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media, queue: "move"))
    end
  end
end
