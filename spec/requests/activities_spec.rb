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
