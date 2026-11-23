# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Activities" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/activity" do
    it "renders the empty state when nothing has happened" do
      get move_activity_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("activities.index.empty_body"))
    end

    it "renders a recorded edit, naming the subject, with a Revert affordance" do
      item = create(:item, :manual, move:, name: "Lamp")
      Items::Rename.new.call(item:, name: "Desk lamp", editor: user)

      get move_activity_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Desk lamp").and include(I18n.t("activities.revert.action"))
    end

    it "labels the current user's own action as 'You'" do
      item = create(:item, :manual, move:, name: "Lamp")
      Items::Rename.new.call(item:, name: "Desk lamp", editor: user)

      get move_activity_path(move)

      expect(response.body).to include(I18n.t("activities.actor.you"))
    end

    it "renders a deleted box with a Restore affordance" do
      box = create(:box, move:, number: "7")
      Boxes::Delete.new.call(box:, actor: user)

      get move_activity_path(move)

      expect(response.body).to include("Box 7").and include(I18n.t("activities.restore.action"))
    end

    # #577 — a deleted photo (Media, now discardable) must name its subject (loaded
    # with_discarded) and offer Restore, same as a box/item.
    it "renders a deleted photo with a Restore affordance" do
      box = create(:box, move:)
      media = create(:media, move:, box:)
      create(:item, move:, box:, source_media: media)
      Photos::Delete.new.call(media:, actor: user)

      get move_activity_path(move)

      expect(response.body)
        .to include(I18n.t("activities.subject.photo")).and include(I18n.t("activities.restore.action"))
    end

    # #582 — once the retention window lapses the Restore button disappears even
    # BEFORE the sweep has hard-deleted the subject (CascadeRestore refuses too),
    # so the feed never offers a restore that would race the purge.
    it "offers no Restore for an expired subject the sweep has not purged yet" do
      box = create(:box, move:, number: "7")
      travel_to((Discardable::RETENTION + 1.day).ago) { Boxes::Delete.new.call(box:, actor: user) }

      get move_activity_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Box 7") # subject row still renders, named
      expect(response.body).not_to include(I18n.t("activities.restore.action"))
    end

    # After the retention sweep hard-deletes a subject, its feed row must still
    # render (activities are append-only history) — with fallback copy and no
    # Restore affordance.
    it "renders a purged subject's row with fallback copy and no Restore affordance" do
      box = create(:box, move:, number: "7")
      Boxes::Delete.new.call(box:, actor: user)
      travel_to((Discardable::RETENTION + 1.day).from_now) { Discards::PurgeExpired.new.call }

      get move_activity_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("activities.subject.unknown"))
      expect(response.body).not_to include(I18n.t("activities.restore.action"))
    end

    # #582 — an item.moved row interpolates its destination box; once the sweep
    # purges that box the copy must fall back, not truncate ("moved Lamp to ").
    it "renders a moved item's row with fallback copy when the destination box was purged" do
      box = create(:box, move:, number: "7")
      target = create(:box, move:, number: "8")
      item = create(:item, :manual, move:, box:, name: "Lamp")
      Items::Move.new.call(item:, target_box: target, mover: user)
      Boxes::Delete.new.call(box: target, actor: user)
      travel_to((Discardable::RETENTION + 1.day).from_now) { Discards::PurgeExpired.new.call }

      get move_activity_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("activities.subject.unknown_box"))
    end

    # #194 — the keyset cursor must survive the round-trip through the load-older
    # link at sub-second precision: occurred_at is timestamp(6), so a whole-second
    # cursor would skip every row inside the boundary second. Seed one PAGE worth
    # plus one extra, all within a single second, and follow the real link: the
    # extra row must still appear on page 2 (a truncated cursor would empty it).
    it "pages past a sub-second boundary without dropping a row" do
      base = Time.utc(2026, 1, 1, 12, 0, 0)
      (ActivitiesController::PAGE + 1).times do |i|
        Activity.create!(
          move:, action: "box.created", source: :web, subject_type: "Box",
          subject_id: SecureRandom.uuid, occurred_at: base + ((i + 1) * 0.001) # 1ms apart, same second
        )
      end

      get move_activity_path(move)
      href = CGI.unescapeHTML(response.body[/href="([^"]*activity\?[^"]*before=[^"]*)"/, 1].to_s)
      expect(href).to be_present
      get href

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(I18n.t("activities.index.empty_body"))
    end
  end

  describe "POST /moves/:move_id/activity/:id/restore" do
    it "restores a deleted box (and its cascade)" do
      box = create(:box, move:, number: "7")
      create(:item, move:, box:)
      Boxes::Delete.new.call(box:, actor: user)
      activity = move.activities.find_by!(action: "box.deleted")

      post move_activity_restore_path(move, activity.id)

      expect(response).to redirect_to(move_activity_path(move))
      expect(Box.exists?(box.id)).to be(true)
      expect(box.items.count).to eq(1)
    end

    it "restores a deleted photo and its items (#577)" do
      box = create(:box, move:)
      media = create(:media, move:, box:)
      item = create(:item, move:, box:, source_media: media)
      Photos::Delete.new.call(media:, actor: user)
      activity = move.activities.find_by!(action: "media.discarded")

      post move_activity_restore_path(move, activity.id)

      expect(response).to redirect_to(move_activity_path(move))
      expect(Media.kept.exists?(media.id)).to be(true)
      expect(Item.kept.exists?(item.id)).to be(true)
    end

    it "rejects a stale restore whose subject the retention sweep already purged" do
      box = create(:box, move:, number: "7")
      Boxes::Delete.new.call(box:, actor: user)
      activity = move.activities.find_by!(action: "box.deleted")
      travel_to((Discardable::RETENTION + 1.day).from_now) { Discards::PurgeExpired.new.call }

      post move_activity_restore_path(move, activity.id), as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("activities.restore.failed")))
      expect(Box.with_discarded.exists?(box.id)).to be(false)
    end

    # #901 — the record was restored (and maybe deleted again) by someone else
    # between the feed render and this click.
    it "says so when the item was already restored meanwhile" do
      item = create(:item, :manual, move:, box: create(:box, move:), name: "Lamp")
      Items::Remove.new.call(item:, actor: user)
      activity = move.activities.find_by!(action: "item.deleted", subject_id: item.id)
      Items::Restore.new.call(item: Item.with_discarded.find(item.id), actor: user)

      post move_activity_restore_path(move, activity.id), as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("activities.restore.not_found")))
        .and include(%(action="remove" target="#{Views::Activities::Index.restore_id(activity.id)}"))
      expect(response.body).not_to include(%(target="#{Views::Activities::Index::ID}"))
    end

    it "says so when the photo was restored and deleted again meanwhile" do
      media = create(:media, move:, box: create(:box, move:))
      Photos::Delete.new.call(media:, actor: user)
      activity = move.activities.find_by!(action: "media.discarded", subject_id: media.id)
      allow(Photos::Restore).to receive(:new)
        .and_return(instance_double(Photos::Restore, call: Dry::Monads::Failure(:stale)))

      post move_activity_restore_path(move, activity.id), as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("activities.restore.stale")))
        .and include(%(action="remove" target="#{Views::Activities::Index.restore_id(activity.id)}"))
      expect(response.body).not_to include(%(target="#{Views::Activities::Index::ID}"))
    end

    # #901 — the old entry describes a deletion that was undone; the photo is
    # deleted again under a newer batch, which only the newer entry may undo.
    it "refuses a superseded delete entry and keeps the newer deletion" do
      media = create(:media, move:, box: create(:box, move:))
      Photos::Delete.new.call(media:, actor: user)
      old_entry = move.activities.find_by!(action: "media.discarded", subject_id: media.id)
      Photos::Restore.new.call(media: Media.with_discarded.find(media.id), actor: user)
      Photos::Delete.new.call(media: Media.find(media.id), actor: user)

      newer_entry = move.activities.where(action: "media.discarded", subject_id: media.id)
                        .where.not(id: old_entry.id).sole
      get move_activity_path(move)
      expect(response.body).not_to include(Views::Activities::Index.restore_id(old_entry.id))
      expect(response.body).to include(Views::Activities::Index.restore_id(newer_entry.id))

      post move_activity_restore_path(move, old_entry.id), as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(CGI.escapeHTML(I18n.t("activities.restore.stale")))
      expect(Media.with_discarded.find(media.id)).to be_discarded
    end

    it "streams the re-rendered feed + a toast (no reload)" do
      box = create(:box, move:, number: "7")
      Boxes::Delete.new.call(box:, actor: user)
      activity = move.activities.find_by!(action: "box.deleted")

      post move_activity_restore_path(move, activity.id), as: :turbo_stream

      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body)
        .to include(%(action="replace" target="#{Views::Activities::Index::ID}"))
        .and include(I18n.t("activities.restore.done"))
      expect(Box.exists?(box.id)).to be(true)
    end

    context "when the item's box is deleted too (#894)" do
      let(:box) { create(:box, move:, number: "7") }
      let(:item) { create(:item, :manual, move:, box:, name: "Lamp") }

      def item_activity
        move.activities.find_by!(action: "item.deleted", subject_id: item.id)
      end

      # The feed page that starts at the box's own `box.deleted` row.
      def entry_href
        box_activity = move.activities.find_by!(action: "box.deleted", subject_id: box.id)
        move_activity_path(move, before: box_activity.occurred_at.iso8601(6),
                                 before_id: ActivitiesController::MAX_UUID)
      end

      before do
        Items::Delete.new.call(item:, actor: user)
        Boxes::Delete.new.call(box:, actor: user)
      end

      it "refuses with 'restore the box first' and links to the box's restore entry" do
        post move_activity_restore_path(move, item_activity.id), as: :turbo_stream

        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body)
            .to include(CGI.escapeHTML(I18n.t("activities.restore.parent_discarded")))
            .and include(%(href="#{entry_href}"))
            .and include(I18n.t("activities.restore.view_box_entry"))
          expect(Item.with_discarded.find(item.id)).to be_discarded
        end
      end

      it "carries the link through the no-JS redirect" do
        post move_activity_restore_path(move, item_activity.id)

        expect(response).to redirect_to(move_activity_path(move))
        expect(flash[:alert]).to eq(I18n.t("activities.restore.parent_discarded"))
        expect(flash[:action_href]).to eq(entry_href)
      end

      it "opens a feed page that starts at the box's restore entry" do
        later = create(:box, move:, number: "99")
        travel(1.minute) { Boxes::Update.new.call(box: later, editor: user, params: { weight_kg: 3 }) }

        get entry_href

        expect(response.body).to include("Box 7").and include(I18n.t("activities.restore.action"))
        expect(response.body).not_to include("Box 99") # newer than the entry: not on this page
      end

      it "refuses a photo restore the same way" do
        media = create(:media, move:, box: create(:box, move:, number: "8"))
        Photos::Delete.new.call(media:, actor: user)
        Boxes::Delete.new.call(box: media.box, actor: user)
        photo_activity = move.activities.find_by!(action: "media.discarded", subject_id: media.id)

        post move_activity_restore_path(move, photo_activity.id), as: :turbo_stream

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include(I18n.t("activities.restore.view_box_entry"))
        expect(Media.with_discarded.find(media.id)).to be_discarded
      end
    end
  end

  describe "POST /moves/:move_id/activity/:id/revert" do
    it "reverts an item edit to the prior value" do
      item = create(:item, :manual, move:, name: "Lamp")
      Items::Rename.new.call(item:, name: "Desk lamp", editor: user)
      activity = move.activities.where(action: "item.updated").last

      post move_activity_revert_path(move, activity.id)

      expect(item.reload.name).to eq("Lamp")
    end

    it "reverts a box description edit to the prior value" do
      box = create(:box, move:, number: "7", description: "Old summary")
      Boxes::Update.new.call(box:, editor: user, params: { description: "New summary" })
      activity = move.activities.where(action: "box.updated").last

      post move_activity_revert_path(move, activity.id)

      expect(box.reload.description).to eq("Old summary")
    end

    it "streams the re-rendered feed + a toast on revert (no reload)" do
      item = create(:item, :manual, move:, name: "Lamp")
      Items::Rename.new.call(item:, name: "Desk lamp", editor: user)
      activity = move.activities.where(action: "item.updated").last

      post move_activity_revert_path(move, activity.id), as: :turbo_stream

      expect(response.body)
        .to include(%(action="replace" target="#{Views::Activities::Index::ID}"))
        .and include(I18n.t("activities.revert.done"))
      expect(item.reload.name).to eq("Lamp")
    end
  end

  describe "authorization" do
    it "forbids a viewer from restoring" do
      box = create(:box, move:, number: "7")
      Boxes::Delete.new.call(box:, actor: user)
      activity = move.activities.find_by!(action: "box.deleted")
      viewer = create(:user)
      move.move_memberships.create!(user: viewer, role: "viewer")
      stub_current_user(viewer)

      post move_activity_restore_path(move, activity.id)

      expect(response).to have_http_status(:forbidden)
      expect(Box.exists?(box.id)).to be(false)
    end
  end
end
