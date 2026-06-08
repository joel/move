# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Unpacking mode" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  it "enters from the box detail and checks an item off" do
    box = create(:box, :with_room, move:, number: "7", status: "unpacking")
    plates = create(:item, move:, box:, name: "Ceramic Plates", presence_state: "in_box")
    create(:item, move:, box:, name: "Glass Bowls", presence_state: "in_box")

    # Enter the checklist from the box detail.
    visit move_box_path(move, box)
    click_link I18n.t("boxes.actions.unpack")

    expect(page).to have_text(I18n.t("unpacking.remaining_title"))
    expect(page).to have_text(I18n.t("unpacking.remaining_count", count: 2, total: 2))

    # Check one item off (the whole row is the remove button) — it settles into
    # the Unpacked section and the remaining count drops.
    click_button "Ceramic Plates"

    expect(plates.reload.presence_state).to eq("removed")
    expect(page).to have_text(I18n.t("unpacking.unpacked_title"))
    expect(page).to have_text(I18n.t("unpacking.remaining_count", count: 1, total: 2))
  end

  it "marks the box unpacked and cascades the remaining items" do
    box = create(:box, :with_room, move:, number: "7", status: "unpacking")
    create(:item, move:, box:, name: "Ceramic Plates", presence_state: "in_box")
    create(:item, move:, box:, name: "Glass Bowls", presence_state: "in_box")

    visit move_box_unpacking_path(move, box)
    # rack_test ignores the turbo_confirm data attribute and submits directly.
    click_button I18n.t("unpacking.complete")

    # Celebration is shown and every item is now removed.
    expect(page).to have_text(I18n.t("unpacking.done_title"))
    expect(box.reload.status).to eq("unpacked")
    expect(box.items.in_box.count).to eq(0)

    # Undo reopens the box back to the checklist.
    click_button I18n.t("unpacking.undo")
    expect(box.reload.status).to eq("unpacking")
    expect(page).to have_text(I18n.t("unpacking.remaining_title"))
  end

  it "is read-only on an archived move" do
    archived = create(:move, :archived, created_by: user)
    box = create(:box, :with_room, move: archived, number: "7", status: "unpacking")
    create(:item, move: archived, box:, name: "Ceramic Plates", presence_state: "in_box")

    visit move_box_unpacking_path(archived, box)

    expect(page).to have_text(I18n.t("unpacking.read_only"))
    expect(page).to have_no_button(I18n.t("unpacking.complete"))
  end
end
