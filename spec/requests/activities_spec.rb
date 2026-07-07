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
