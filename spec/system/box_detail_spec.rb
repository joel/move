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
