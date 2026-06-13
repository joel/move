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

    it "shows the (auto-saving) edit form to an editor but a read-only view to a viewer" do
      as(admin)
      get move_item_path(move, item)
      # The inline save-status badge marks the editable, auto-saving form.
      expect(response.body).to include(Components::Ui::SaveStatus::ID)

      as(viewer)
      get move_item_path(move, item)
      aggregate_failures do
        expect(response.body).not_to include(Components::Ui::SaveStatus::ID)
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

  describe "per-photo review" do
    let(:box) { create(:box, move:, number: "1") }
    let(:media) { create(:media, move:, box:) }

    it "shows the edit/add affordances to an editor but read-only to a viewer" do
      create(:item, move:, box:, source_media: media, name: "Mug", review_state: "pending_review")

      as(admin)
      get move_box_review_photo_path(move, box, media)
      expect(response.body).to include(I18n.t("reviews.photo.add_placeholder"))

      as(viewer)
      get move_box_review_photo_path(move, box, media)
      aggregate_failures do
        expect(response.body).to include(I18n.t("reviews.photo.view_only"))
        expect(response.body).not_to include(I18n.t("reviews.photo.add_placeholder"))
      end
    end
  end
end
