# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Box detail & lifecycle" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  it "edits a box, derives volume, and walks the seal/unseal lifecycle" do
    box = create(:box, move:, number: "1", status: "packing", room: nil)

    visit move_box_path(move, box)
    expect(page).to have_text("Box #001")

    # Sealing is blocked until the box has a room.
    click_button I18n.t("boxes.actions.seal")
    expect(page).to have_text(I18n.t("boxes.transition.room_required"))
    expect(box.reload.status).to eq("packing")

    # Edit: assign a room and dimensions.
    visit edit_move_box_path(move, box)
    fill_in I18n.t("boxes.form.room"), with: "Kitchen"
    fill_in I18n.t("boxes.form.length_cm"), with: "40"
    fill_in I18n.t("boxes.form.width_cm"), with: "30"
    fill_in I18n.t("boxes.form.height_cm"), with: "25"
    click_button I18n.t("boxes.edit.submit")

    # Detail now shows the room, derived volume, and allows sealing.
    expect(page).to have_text("Kitchen").and have_text("0.030 m³")
    click_button I18n.t("boxes.actions.seal")
    expect(box.reload.status).to eq("sealed")

    # A sealed box can be unsealed.
    click_button I18n.t("boxes.actions.unseal")
    expect(box.reload.status).to eq("packing")
  end

  it "shows the review CTA for a box whose only items are needs_correction (#146)" do
    box = create(:box, move:, number: "2", status: "packing")
    media = create(:media, move:, box:)
    create(:item, move:, box:, source_media: media, name: "Magazines", review_state: "needs_correction")

    visit move_box_path(move, box)

    expect(page).to have_link(I18n.t("boxes.show.pending_review", count: 1))
  end

  it "hides the review CTA for a needs_correction item with no source photo (#146)" do
    box = create(:box, move:, number: "3", status: "packing")
    # No source_media → the photo-keyed walk can't review it (resolved on C3), so
    # the badge must not advertise a CTA that dead-ends on "nothing to review".
    create(:item, move:, box:, name: "Loose papers", review_state: "needs_correction")

    visit move_box_path(move, box)

    expect(page).to have_text("Box #003")
    expect(page).to have_no_link(I18n.t("boxes.show.pending_review", count: 1))
  end

  it "ignores a moved-in item whose source photo belongs to another box (#146)" do
    foreign_media = create(:media, move:, box: create(:box, move:, number: "4"))
    box = create(:box, move:, number: "5", status: "packing")
    # In this box, but its source photo lives in box 4 — the box-5 walk can't reach
    # it, so the badge must not count it.
    create(:item, move:, box:, source_media: foreign_media, review_state: "needs_correction")

    visit move_box_path(move, box)

    expect(page).to have_text("Box #005")
    expect(page).to have_no_link(I18n.t("boxes.show.pending_review", count: 1))
  end

  it "is read-only on an archived move" do
    archived = create(:move, :archived, created_by: user)
    box = create(:box, :with_room, move: archived, number: "1", status: "packing")

    visit move_box_path(archived, box)

    expect(page).to have_text("Box #001")
    expect(page).to have_text(I18n.t("boxes.show.archived"))
    expect(page).to have_no_button(I18n.t("boxes.actions.seal"))
    expect(page).to have_no_link(I18n.t("boxes.show.edit"))
  end
end
