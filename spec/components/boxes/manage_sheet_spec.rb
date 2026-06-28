# frozen_string_literal: true

require "rails_helper"

# The Manage-box sheet (Components::Boxes::ManageSheet) renders button_to forms,
# so it is exercised through the box-detail page (full view context) rather than
# in isolation — the repo convention for button_to-bearing components.
RSpec.describe "Box detail — Manage sheet", type: :request do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  it "renders the ⋮ trigger and the bottom sheet with the box's secondary actions" do
    box = create(:box, :with_room, move:, number: "1", status: "packing")

    get move_box_path(move, box)

    aggregate_failures do
      expect(response.body).to include("ha-sheet")
      expect(response.body).to include(I18n.t("boxes.manage.trigger"))       # ⋮ aria-label
      expect(response.body).to include(I18n.t("boxes.manage.title", number: "001"))
      expect(response.body).to include(I18n.t("boxes.actions.seal"))         # lifecycle
      expect(response.body).to include(I18n.t("boxes.actions.print_label"))
      expect(response.body).to include(I18n.t("boxes.actions.print_manifest"))
      expect(response.body).to include(I18n.t("boxes.actions.edit"))
      expect(response.body).to include(I18n.t("boxes.actions.delete"))
    end
  end

  it "surfaces the box's dimensions, volume and weight (demoted off the header) in the sheet" do
    box = create(:box, :with_dimensions, move:, number: "1", weight_kg: 9)

    get move_box_path(move, box)

    aggregate_failures do
      expect(response.body).to include(I18n.t("boxes.manage.title", number: "001"))
      expect(response.body).to include("40 × 30 × 25 cm") # dimensions
      expect(response.body).to include("0.030 m³")        # derived volume
      expect(response.body).to include(I18n.t("boxes.show.weight"))
    end
  end

  it "hides the lifecycle / edit / delete actions from a viewer (print stays)" do
    viewer = create(:user)
    create(:move_membership, move:, user: viewer, role: "viewer")
    box = create(:box, :with_room, move:, number: "1", status: "packing")
    stub_current_user(viewer)

    get move_box_path(move, box)

    aggregate_failures do
      expect(response.body).to include(I18n.t("boxes.actions.print_label"))
      expect(response.body).not_to include(I18n.t("boxes.actions.seal"))
      expect(response.body).not_to include(I18n.t("boxes.actions.edit"))
      expect(response.body).not_to include(I18n.t("boxes.actions.delete"))
    end
  end

  it "promotes the forward step to the hero and keeps only the backward step in the sheet" do
    box = create(:box, :with_room, move:, number: "1", status: "sealed")

    get move_box_path(move, box)

    aggregate_failures do
      expect(response.body).to include(I18n.t("boxes.actions.in_transit")) # hero (forward)
      expect(response.body).to include(I18n.t("boxes.actions.unseal"))     # sheet (backward)
    end
  end

  it "routes Seal through the describe-before-sealing dialog when a description is missing" do
    box = create(:box, :with_room, move:, number: "1", status: "packing")
    create(:item, move:, box:, name: "Mug") # item_count positive, still no description

    get move_box_path(move, box)

    expect(response.body).to include(seal_move_box_path(move, box)) # the lazy seal frame
  end
end
