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

  # #891 — a conflict-only photo (its latest run matched confirmed items and
  # added none) explains the match in the empty state and links to each match.
  describe "GET .../review/photo/:media_id — conflict-only photo (#891)" do
    let(:lamp) { create(:item, move:, box:, name: "Lamp", review_state: "confirmed") }

    def conflict_on(item, run: create(:recognition_run, :succeeded, move:, box:, media:))
      create(:recognition_suggestion, :conflict, move:, box:, media:, recognition_run: run, item:)
      run
    end

    def item_list
      response.parsed_body.at_css("##{Components::Reviews::ItemList::ID}")
    end

    it "explains the match and links to every matched item" do
      run = conflict_on(lamp)
      rug = create(:item, move:, box:, name: "Rug", review_state: "confirmed")
      conflict_on(rug, run:)

      get move_box_review_photo_path(move, box, media)

      expect(response).to have_http_status(:ok)
      expect(item_list.text).to include(I18n.t("reviews.photo.conflict_title"))
      expect(item_list.text).to include(I18n.t("reviews.photo.conflict_description", count: 2))
      expect(item_list.text).not_to include(I18n.t("reviews.photo.empty_title"))
      expect(item_list.at_css(%(a[href="#{move_item_path(move, lamp)}"]))&.text).to include("Lamp")
      expect(item_list.at_css(%(a[href="#{move_item_path(move, rug)}"]))&.text).to include("Rug")
    end

    it "keeps retake, rescan and delete available" do
      conflict_on(lamp)

      get move_box_review_photo_path(move, box, media)

      page = response.parsed_body
      expect(page.at_css(%(form[action="#{move_box_review_retake_photo_path(move, box, media)}"]))).to be_present
      expect(page.at_css('input[name="rerun_recognition"]')).to be_present
      expect(page.at_css(%(form[action="#{move_box_review_photo_path(move, box, media)}"] input[name="_method"][value="delete"]))).to be_present
    end

    it "shows the plain empty state once the matched item is deleted" do
      conflict_on(lamp)
      lamp.discard!

      get move_box_review_photo_path(move, box, media)

      expect(item_list.text).to include(I18n.t("reviews.photo.empty_title"))
      expect(item_list.text).not_to include(I18n.t("reviews.photo.conflict_title"))
    end

    it "ignores a conflict recorded only by an older run" do
      conflict_on(lamp, run: create(:recognition_run, :succeeded, move:, box:, media:, created_at: 1.hour.ago))
      create(:recognition_run, :succeeded, move:, box:, media:)

      get move_box_review_photo_path(move, box, media)

      expect(item_list.text).to include(I18n.t("reviews.photo.empty_title"))
    end

    it "lists the photo's own items, then the matches still to settle (#881)" do
      conflict_on(lamp)
      detected(name: "Kettle")

      get move_box_review_photo_path(move, box, media)

      expect(item_list.text).to include("Kettle").and include(I18n.t("reviews.photo.conflict_title"))
      expect(item_list.text).not_to include(I18n.t("reviews.photo.conflict_description", count: 1))
    end
  end

  describe "nav arrows on the box walk (#699)" do
    # A walk photo older than `media` (the let is captured "now"); the box walk
    # orders oldest capture first.
    def walk_photo(captured_at:, name: "Thing", state: "pending_review")
      photo = create(:media, move:, box:, captured_at:)
      create(:item, move:, box:, source_media: photo, name:, review_state: state)
      photo
    end

    it "links both neighbours from a mid-walk photo, each carrying the pending-add guard" do
      oldest = walk_photo(captured_at: 2.hours.ago)
      middle = walk_photo(captured_at: 1.hour.ago)
      detected(name: "Lamp") # `media`, captured now — the walk's end

      get move_box_review_photo_path(move, box, middle)

      guard = %([^>]*data-action="click->pending-add#guardVisit")
      prev_href = Regexp.escape(move_box_review_photo_path(move, box, oldest))
      next_href = Regexp.escape(move_box_review_photo_path(move, box, media))
      expect(response.body)
        .to match(/<a href="#{prev_href}"[^>]*aria-label="#{I18n.t("reviews.photo.nav.previous")}"#{guard}/)
      expect(response.body)
        .to match(/<a href="#{next_href}"[^>]*aria-label="#{I18n.t("reviews.photo.nav.next")}"#{guard}/)
    end

    it "disables prev at the start of the walk without dropping its label" do
      oldest = walk_photo(captured_at: 2.hours.ago)
      detected(name: "Lamp")

      get move_box_review_photo_path(move, box, oldest)

      expect(response.body).not_to match(/<a [^>]*aria-label="#{I18n.t("reviews.photo.nav.previous")}"/)
      expect(response.body)
        .to match(/<span [^>]*aria-disabled="true" aria-label="#{I18n.t("reviews.photo.nav.previous")}"/)
      expect(response.body).to match(/<a [^>]*aria-label="#{I18n.t("reviews.photo.nav.next")}"/)
    end

    it "disables next at the end of the walk while the advance still offers Finish" do
      walk_photo(captured_at: 2.hours.ago)
      detected(name: "Lamp", review_state: "confirmed") # nothing pending → plain advance link

      get move_box_review_photo_path(move, box, media)

      # The nav boundary is a disabled arrow — distinct from the advance
      # control's finish fallback, which still exits to the box.
      expect(response.body)
        .to match(/<span [^>]*aria-disabled="true" aria-label="#{I18n.t("reviews.photo.nav.next")}"/)
      expect(response.body).to include(I18n.t("reviews.photo.finish"))
      expect(response.body).to include(%(href="#{move_box_path(move, box)}"))
    end

    it "reaches an already-marked photo with prev (the walk is stable, not state-filtered)" do
      marked = walk_photo(captured_at: 2.hours.ago, state: "confirmed")
      detected(name: "Lamp")

      get move_box_review_photo_path(move, box, media)

      expect(response.body).to match(
        /<a href="#{Regexp.escape(move_box_review_photo_path(move, box, marked))}"[^>]*aria-label="#{I18n.t("reviews.photo.nav.previous")}"/
      )
    end

    it "hides the pair entirely on a single-photo walk" do
      detected(name: "Lamp")

      get move_box_review_photo_path(move, box, media)

      expect(response.body).not_to include(%(aria-label="#{I18n.t("reviews.photo.nav.label")}"))
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
      older = create(:media, move:, box: other_box, captured_at: 1.hour.ago)
      create(:item, move:, box: other_box, source_media: older, review_state: "pending_review")

      post move_box_review_mark_reviewed_path(move, box, media, queue: "move")

      expect(item.reload.review_state).to eq("confirmed")
      expect(response).to redirect_to(move_box_review_photo_path(move, other_box, older, queue: "move"))
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
    it "renames the item and echoes the canonical name + version (no navigation)" do
      item = detected(name: "Cofee machine")

      patch move_box_review_rename_item_path(move, box, media, item), params: { name: "Coffee machine" }

      expect(response).to have_http_status(:ok)
      expect(item.reload.name).to eq("Coffee machine")
      expect(response.parsed_body).to eq(
        "name" => "Coffee machine", "version" => Components::Reviews::ItemRow.version(item)
      )
    end

    # #692: the add's list replacement and a flushed rename race. Whichever lands
    # last on the client, the versions decide: a list read BEFORE the rename
    # committed carries an older version than the rename's echo (so the client
    # keeps the echoed name), and a list read AFTER carries the echo's version
    # (so the snapshot, which then holds the new name, is equally trusted).
    it "orders an add's list snapshot against the rename echo by version" do
      item = detected(name: "Coffee machine")

      post move_box_review_add_item_path(move, box, media), params: { item: { name: "Kettle" } }, as: :turbo_stream
      before_rename = row_state(item)

      patch move_box_review_rename_item_path(move, box, media, item), params: { name: "Espresso machine" }
      echo = response.parsed_body

      post move_box_review_add_item_path(move, box, media), params: { item: { name: "Toaster" } }, as: :turbo_stream
      after_rename = row_state(item)

      expect(before_rename[:name]).to eq("Coffee machine")
      expect(before_rename[:version]).to be < echo["version"]
      expect(after_rename).to eq(name: "Espresso machine", version: echo["version"])
    end

    def row_state(item)
      # A turbo_stream body has no registered parser, so parsed_body is the raw string.
      row = Nokogiri::HTML(response.parsed_body.to_s).at_css("##{Components::Reviews::ItemRow.dom_id(item)}")
      { name: row.at_css("[data-inline-rename-target='input']")["value"],
        version: Integer(row["data-inline-rename-version-value"]) }
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
      # Removing the box's only detection during packing is mis-detection
      # cleanup — it must never auto-complete the box (#755).
      expect(box.reload.status).to eq("packing")
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

    it "refuses to add an item to an unpacked (terminal) box (#855)" do
      unpacked = create(:box, :with_room, move:, status: "unpacked")
      photo = create(:media, move:, box: unpacked)

      expect do
        post move_box_review_add_item_path(move, unpacked, photo), params: { item: { name: "Kettle" } }
      end.not_to change(Item, :count)

      expect(flash[:alert]).to eq(I18n.t("reviews.flash.add_failed"))
    end

    it "answers 422 with an alert toast as a Turbo Stream for an unpacked box (#855)" do
      unpacked = create(:box, :with_room, move:, status: "unpacked")
      photo = create(:media, move:, box: unpacked)

      post move_box_review_add_item_path(move, unpacked, photo), params: { item: { name: "Kettle" } },
                                                                 as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("reviews.flash.add_failed"))
      expect(unpacked.items.reload).to be_empty
    end

    it "hides the add-item form on an unpacked box's photo, keeps it on a sealed one (#855)" do
      unpacked = create(:box, :with_room, move:, status: "unpacked")
      sealed = create(:box, :sealed, move:)
      unpacked_photo = create(:media, move:, box: unpacked)
      sealed_photo = create(:media, move:, box: sealed)

      get move_box_review_photo_path(move, unpacked, unpacked_photo)
      expect(response.body).not_to include(move_box_review_add_item_path(move, unpacked, unpacked_photo))

      get move_box_review_photo_path(move, sealed, sealed_photo)
      expect(response.body).to include(move_box_review_add_item_path(move, sealed, sealed_photo))
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

  describe "find-list pin on review rows (#749)" do
    it "renders the pin toggle per row on a sealed box, reflecting the current user's pins" do
      sealed = create(:box, :sealed, move:)
      photo = create(:media, move:, box: sealed)
      lamp = create(:item, move:, box: sealed, source_media: photo, name: "Lamp",
                           review_state: "pending_review")
      desk = create(:item, move:, box: sealed, source_media: photo, name: "Desk",
                           review_state: "pending_review")
      create(:find_list_entry, move:, user:, item: desk)

      get move_box_review_photo_path(move, sealed, photo)

      # Pin vs unpin share one URL string (POST vs DELETE), so state is
      # asserted on the rendered labels, never the path helpers.
      aggregate_failures do
        expect(response.body).to include(%(id="#{Components::FindLists::Toggle.dom_id(lamp)}"))
        expect(response.body).to include(I18n.t("find_lists.toggle.add", name: "Lamp"))
        expect(response.body).to include(I18n.t("find_lists.toggle.remove", name: "Desk"))
      end
    end

    it "renders no pin toggles while the box is packing" do
      detected(name: "Lamp")

      get move_box_review_photo_path(move, box, media)

      expect(response.body).not_to include("find-list-toggle")
    end

    it "renders working pin toggles for a viewer (personal rows need no editable move)" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)
      sealed = create(:box, :sealed, move:)
      photo = create(:media, move:, box: sealed)
      create(:item, move:, box: sealed, source_media: photo, name: "Lamp",
                    review_state: "pending_review")

      get move_box_review_photo_path(move, sealed, photo)

      expect(response.body).to include(I18n.t("find_lists.toggle.add", name: "Lamp"))
    end

    it "keeps pin state on the post-add list stream" do
      sealed = create(:box, :sealed, move:)
      photo = create(:media, move:, box: sealed)
      desk = create(:item, move:, box: sealed, source_media: photo, name: "Desk",
                           review_state: "pending_review")
      create(:find_list_entry, move:, user:, item: desk)

      post move_box_review_add_item_path(move, sealed, photo),
           params: { item: { name: "Mug" } }, as: :turbo_stream

      aggregate_failures do
        expect(response.body).to include(I18n.t("find_lists.toggle.remove", name: "Desk"))
        expect(response.body).to include(I18n.t("find_lists.toggle.add", name: "Mug"))
      end
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
      expect(flash[:action_href]).to be_nil
    end

    context "when the photo held the last in-box items of an unpacking box (#838)" do
      let(:box) { create(:box, move:, number: "3", status: "unpacking") }

      it "completes the source box and links to it from the toast (UX rule 1)" do
        detected(name: "Lamp")
        target = create(:box, move:, number: "8", status: "unpacking")

        patch move_box_review_move_photo_path(move, box, media), params: { target_box_id: target.id }

        aggregate_failures do
          expect(box.reload.status).to eq("unpacked")
          expect(target.reload.status).to eq("unpacking")
          expect(response).to redirect_to(move_box_path(move, target))
          expect(flash[:notice]).to eq(I18n.t("reviews.flash.photo_moved_box_unpacked", number: "8", source: "3"))
          expect(flash[:action_href]).to eq(move_box_path(move, box))
          expect(flash[:action_label]).to eq(I18n.t("reviews.flash.view_box"))
        end
      end

      it "keeps the plain toast while other in-box items remain" do
        detected(name: "Lamp")
        create(:item, :manual, move:, box:) # another photo's / manual item stays behind
        target = create(:box, move:, number: "8")

        patch move_box_review_move_photo_path(move, box, media), params: { target_box_id: target.id }

        expect(box.reload.status).to eq("unpacking")
        expect(flash[:notice]).to eq(I18n.t("reviews.flash.photo_moved", number: "8"))
        expect(flash[:action_href]).to be_nil
      end

      it "stays in the queue walk and still links to the completed box" do
        detected(name: "Lamp")
        target = create(:box, move:, number: "8")

        patch move_box_review_move_photo_path(move, box, media, queue: "move"), params: { target_box_id: target.id }

        expect(response).to redirect_to(move_box_review_photo_path(move, target, media, queue: "move"))
        expect(flash[:action_href]).to eq(move_box_path(move, box))
      end
    end

    it "rejects a target outside this Move (scoped to @move.boxes) without moving the photo" do
      detected(name: "Lamp")
      foreign = create(:box, move: create(:move)) # another Move → not found in @move.boxes

      patch move_box_review_move_photo_path(move, box, media), params: { target_box_id: foreign.id }

      expect(media.reload.box_id).to eq(box.id)
      # The cross-Move box id resolves to nil under @move.boxes, so it's :box_missing.
      expect(flash[:alert]).to eq(I18n.t("reviews.flash.move_photo_errors.box_missing"))
    end

    # #874: a concurrent request wins between the controller loading @media and
    # Photos::Move taking the box lock. The photo is no longer reachable under
    # @box, so the old "back to this photo" redirect would 404.
    context "when a concurrent request wins the race (#874)" do
      let(:target) { create(:box, move:, number: "7") }

      # Runs `race` right before the action's pre-lock validation — after the
      # controller loaded @media, before the box lock is taken.
      def race_before_lock(race)
        allow(Photos::Move).to receive(:new).and_wrap_original do |original|
          original.call.tap do |action|
            allow(action).to(receive(:validate).and_wrap_original do |validate, *args|
              race.call
              validate.call(*args)
            end)
          end
        end
      end

      # A concurrent move kept relocating the photo while we waited on the lock:
      # the action gives up with Failure(:box_changed) and writes nothing.
      def race_box_changed(to:)
        allow(Photos::Move).to receive(:new).and_wrap_original do |original|
          original.call.tap do |action|
            allow(action).to receive(:relocate) do
              Media.find(media.id).update!(box: to)
              Dry::Monads::Failure(:box_changed)
            end
          end
        end
      end

      it "lands on the box with a deleted alert when a concurrent delete wins" do
        detected(name: "Lamp")
        race_before_lock(-> { Photos::Delete.new.call(media: Media.find(media.id), actor: user) })

        patch move_box_review_move_photo_path(move, box, media), params: { target_box_id: target.id }

        expect(response).to redirect_to(move_box_path(move, box))
        expect(flash[:alert]).to eq(I18n.t("reviews.flash.move_photo_errors.photo_deleted"))
        follow_redirect!
        expect(response).to have_http_status(:ok)
      end

      it "lands on the review queue when a concurrent delete wins in queue mode" do
        detected(name: "Lamp")
        race_before_lock(-> { Photos::Delete.new.call(media: Media.find(media.id), actor: user) })

        patch move_box_review_move_photo_path(move, box, media, queue: "move"), params: { target_box_id: target.id }

        expect(response).to redirect_to(move_review_path(move))
        expect(flash[:alert]).to eq(I18n.t("reviews.flash.move_photo_errors.photo_deleted"))
        follow_redirect!
        expect(response).to have_http_status(:ok)
      end

      it "lands on the box list when a concurrent box delete took the photo with it" do
        detected(name: "Lamp")
        race_before_lock(-> { Boxes::Delete.new.call(box: Box.find(box.id), actor: user) })

        patch move_box_review_move_photo_path(move, box, media), params: { target_box_id: target.id }

        expect(response).to redirect_to(move_boxes_path(move))
        expect(flash[:alert]).to eq(I18n.t("reviews.flash.move_photo_errors.box_deleted"))
        follow_redirect!
        expect(response).to have_http_status(:ok)
      end

      it "lands on the photo's current box when a concurrent move wins" do
        detected(name: "Lamp")
        elsewhere = create(:box, move:, number: "9")
        race_box_changed(to: elsewhere)

        patch move_box_review_move_photo_path(move, box, media), params: { target_box_id: target.id }

        expect(response).to redirect_to(move_box_path(move, elsewhere))
        expect(flash[:alert]).to eq(I18n.t("reviews.flash.move_photo_errors.moved_elsewhere", number: "9"))
        follow_redirect!
        expect(response).to have_http_status(:ok)
      end

      it "lands on the review queue when a concurrent move wins in queue mode" do
        detected(name: "Lamp")
        elsewhere = create(:box, move:, number: "9")
        race_box_changed(to: elsewhere)

        patch move_box_review_move_photo_path(move, box, media, queue: "move"), params: { target_box_id: target.id }

        # Not the photo's review URL in `elsewhere`: that would embed an unlocked
        # read and 404 again if another move lands before the browser follows it.
        expect(response).to redirect_to(move_review_path(move))
        expect(flash[:alert]).to eq(I18n.t("reviews.flash.move_photo_errors.moved_elsewhere", number: "9"))
        follow_redirect!
        expect(response).to have_http_status(:ok)
      end
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

    it "refuses while the photo's recognition is still running and keeps the photo (#854)" do
      create(:recognition_run, :processing, move:, box:, media:)

      delete move_box_review_photo_path(move, box, media)

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
      expect(flash[:alert]).to eq(I18n.t("reviews.flash.photo_delete_recognition_in_flight"))
      expect(Media.kept.exists?(media.id)).to be(true)
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

    # #933 — the photo was deleted between the page load and the retake's lock:
    # going back to the photo page would 404.
    it "redirects to the box when a concurrent delete won the race" do
      allow(Captures::Retake).to receive(:new)
        .and_return(instance_double(Captures::Retake, call: Dry::Monads::Failure(:not_found)))

      post move_box_review_retake_photo_path(move, box, media), params: { file: upload }

      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:alert]).to eq(I18n.t("reviews.flash.retake_errors.not_found"))
    end

    it "redirects to the review queue in queue mode when a concurrent delete won the race" do
      allow(Captures::Retake).to receive(:new)
        .and_return(instance_double(Captures::Retake, call: Dry::Monads::Failure(:not_found)))

      post move_box_review_retake_photo_path(move, box, media, queue: "move"), params: { file: upload }

      expect(response).to redirect_to(move_review_path(move))
    end
  end

  describe "queue mode (?queue=move) — the Move-wide walk (#654)" do
    def pending_photo(box:, captured_at:)
      photo = create(:media, move:, box:, captured_at:)
      create(:item, move:, box:, source_media: photo, review_state: "pending_review")
      photo
    end

    it "advances across box boundaries to the next-newest remaining pending photo (#687)" do
      detected(name: "Lamp") # in `box`, on `media` (captured now)
      other_box = create(:box, move:, number: "42")
      older = pending_photo(box: other_box, captured_at: 1.hour.ago)

      get move_box_review_photo_path(move, box, media, queue: "move")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(move_box_review_photo_path(move, other_box, older, queue: "move"))
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
        # A single-photo walk has no neighbours — the nav pair hides (#699).
        expect(response.body).not_to include(%(aria-label="#{I18n.t("reviews.photo.nav.label")}"))
      end
    end

    it "prev skips a just-marked photo and crosses boxes to the nearest newer pending one (#699)" do
      detected(name: "Lamp") # `media` in `box`, captured now — the newest pending
      marked_box = create(:box, move:, number: "7")
      marked = create(:media, move:, box: marked_box, captured_at: 1.hour.ago)
      create(:item, move:, box: marked_box, source_media: marked, review_state: "confirmed")
      oldest_box = create(:box, move:, number: "42")
      oldest = pending_photo(box: oldest_box, captured_at: 2.hours.ago)

      get move_box_review_photo_path(move, oldest_box, oldest, queue: "move")

      # The marked mid photo left the pending set ("marked is done"); prev
      # lands on the newest pending photo, in ITS box, threading the queue.
      expect(response.body).to match(
        /<a href="#{Regexp.escape(move_box_review_photo_path(move, box, media,
                                                             queue: "move"))}"[^>]*aria-label="#{I18n.t("reviews.photo.nav.previous")}"/
      )
      expect(response.body).not_to include(move_box_review_photo_path(move, marked_box, marked, queue: "move"))
    end

    it "prev reaches an ignored (still-pending) photo (#699)" do
      detected(name: "Lamp") # newest pending
      mid = pending_photo(box:, captured_at: 1.hour.ago)
      oldest = pending_photo(box:, captured_at: 2.hours.ago)

      get move_box_review_photo_path(move, box, oldest, queue: "move")

      expect(response.body).to match(
        /<a href="#{Regexp.escape(move_box_review_photo_path(move, box, mid, queue: "move"))}"[^>]*aria-label="#{I18n.t("reviews.photo.nav.previous")}"/
      )
    end

    it "disables prev at the newest pending photo (#699)" do
      detected(name: "Lamp") # newest pending
      pending_photo(box:, captured_at: 1.hour.ago)

      get move_box_review_photo_path(move, box, media, queue: "move")

      expect(response.body).not_to match(/<a [^>]*aria-label="#{I18n.t("reviews.photo.nav.previous")}"/)
      expect(response.body)
        .to match(/<span [^>]*aria-disabled="true" aria-label="#{I18n.t("reviews.photo.nav.previous")}"/)
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
      # walk must offer the NEXT one down the newest-first queue (never back up
      # to the newest)...
      get move_box_review_photo_path(archived, archived_box, photos[1], queue: "move")
      expect(response.body).to include(move_box_review_photo_path(archived, archived_box, photos[0], queue: "move"))
      # The newest photo is reachable ONLY through the prev nav arrow (#699) —
      # the advance/Ignore controls never point backward, so its href appears
      # exactly once, as the labelled nav anchor.
      backward = move_box_review_photo_path(archived, archived_box, photos[2], queue: "move")
      expect(response.body.scan(%(href="#{backward}")).count).to eq(1)
      expect(response.body).to match(
        /<a href="#{Regexp.escape(backward)}"[^>]*aria-label="#{I18n.t("reviews.photo.nav.previous")}"/
      )

      # ...and from the end of the walk (the oldest), finish back to the queue.
      get move_box_review_photo_path(archived, archived_box, photos[0], queue: "move")
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
