# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GalleryGroups" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/gallery/groups/:id" do
    it "renders the family as an unpacking checklist with box/room locators" do
      kitchen = create(:room, move:, name: "Kitchen")
      box_two = create(:box, move:, number: "2", room: kitchen)
      box_ten = create(:box, move:, number: "10")
      create(:item, :auto_confirmed, move:, box: box_two, name: "AA battery")
      create(:item, :auto_confirmed, move:, box: box_ten, name: "AAA battery")
      Clusters::Recompute.new.call(move:)
      cluster = move.item_clusters.sole

      get move_gallery_group_path(move, cluster)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(cluster.label)
      expect(response.body).to include("Box 2 · Kitchen").and include("Box 10")
      # Box 2's member listed before box 10's — the sweep order.
      expect(response.body.index("AA battery")).to be < response.body.index("AAA battery")
    end

    it "redirects a retired cluster id back to the fresh Groups view" do
      get move_gallery_group_path(move, SecureRandom.uuid)

      expect(response).to redirect_to(move_gallery_path(move, view: "groups"))
      expect(flash[:alert]).to eq(I18n.t("gallery_groups.show.gone"))
    end
  end
end
