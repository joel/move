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
