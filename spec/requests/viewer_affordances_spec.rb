# frozen_string_literal: true

require "rails_helper"

# #95 — a viewer (read-only member) must not be shown mutating affordances on any
# move-scoped surface (the server already 403s; this is the UX side). For each
# surface we assert the editor sees the control and the viewer does not.
RSpec.describe "Viewer read-only affordances" do
  let(:admin) { create(:user) }
  let(:viewer) { create(:user) }
  let(:move) { create(:move, created_by: admin) } # creator → admin (editor)

  before do
    create(:move_membership, move:, user: viewer, role: "viewer")
    stub_current_tenant("acme")
  end

  def as(user) = stub_current_user(user)

  describe "boxes home" do
    it "shows 'Add box' to an editor but not a viewer" do
      as(admin)
      get move_boxes_path(move)
      expect(response.body).to include(I18n.t("boxes.index.add"))

      as(viewer)
      get move_boxes_path(move)
      expect(response.body).not_to include(I18n.t("boxes.index.add"))
    end
  end

  describe "box detail" do
    let(:box) { create(:box, move:, number: "1", status: "packing") }

    it "shows edit + seal to an editor but not a viewer" do
      as(admin)
      get move_box_path(move, box)
      expect(response.body).to include(I18n.t("boxes.show.edit")).and include(I18n.t("boxes.actions.seal"))

      as(viewer)
      get move_box_path(move, box)
      aggregate_failures do
        expect(response.body).not_to include(I18n.t("boxes.show.edit"))
        expect(response.body).not_to include(I18n.t("boxes.actions.seal"))
        expect(response.body).to include(I18n.t("boxes.show.view_only"))
      end
    end
  end

  describe "item detail" do
    let(:box) { create(:box, move:, number: "1") }
    let(:item) { create(:item, move:, box:, name: "Lamp") }

    it "shows the edit form/save to an editor but a read-only view to a viewer" do
      as(admin)
      get move_item_path(move, item)
      expect(response.body).to include(I18n.t("items.show.save"))

      as(viewer)
      get move_item_path(move, item)
      aggregate_failures do
        expect(response.body).not_to include(I18n.t("items.show.save"))
        expect(response.body).not_to include(I18n.t("items.show.remove"))
        expect(response.body).to include(I18n.t("items.show.view_only"))
        expect(response.body).to include("Lamp") # the detail is still shown
      end
    end
  end

  describe "unpacking checklist" do
    let(:box) { create(:box, move:, number: "1", status: "unpacking") }

    it "shows the complete CTA to an editor but not a viewer" do
      create(:item, move:, box:, name: "Plate")

      as(admin)
      get move_box_unpacking_path(move, box)
      expect(response.body).to include(I18n.t("unpacking.complete"))

      as(viewer)
      get move_box_unpacking_path(move, box)
      aggregate_failures do
        expect(response.body).not_to include(I18n.t("unpacking.complete"))
        expect(response.body).to include(I18n.t("unpacking.read_only"))
      end
    end
  end

  describe "review queue" do
    let(:box) { create(:box, move:, number: "1") }

    it "shows keep/correct to an editor but not a viewer" do
      create(:recognition_suggestion, move:, box:, proposed_name: "Mug")

      as(admin)
      get move_box_review_index_path(move, box)
      expect(response.body).to include(I18n.t("reviews.actions.keep"))

      as(viewer)
      get move_box_review_index_path(move, box)
      expect(response.body).not_to include(I18n.t("reviews.actions.keep"))
    end
  end
end
