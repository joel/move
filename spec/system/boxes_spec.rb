# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Boxes Home" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }

  before do
    login_as(user: user)
    # On a real request the subdomain elevator sets the tenant; here we resolve
    # against the public template, so stub the controller's tenant check.
    stub_current_tenant("acme")
  end

  it "shows the empty state and adds the first box end to end" do
    visit move_boxes_path(move)

    expect(page).to have_text("My Boxes").and have_text("Seattle Relocation")
    expect(page).to have_text(I18n.t("boxes.empty.title"))

    visit new_move_box_path(move)
    fill_in I18n.t("boxes.form.room"), with: "Kitchen"
    click_on I18n.t("boxes.form.submit")

    expect(page).to have_current_path(move_boxes_path(move), ignore_query: true)
    expect(page).to have_text("Box 01").and have_text("Kitchen")
    expect(move.boxes.reload.count).to eq(1)
  end

  it "renders per-box status and a missing-dimensions warning" do
    create(:box, move:, number: "1", status: "sealed",
                 room: create(:room, move:, name: "Kitchen"))
    create(:box, move:, number: "2", status: "packing") # no dimensions

    visit move_boxes_path(move)

    expect(page).to have_text(I18n.t("boxes.status.sealed"))
    expect(page).to have_text(I18n.t("boxes.status.packing"))
    expect(page).to have_text(I18n.t("boxes.card.missing_dimensions"))
  end

  it "offers reuse-dimensions chips on the add-box form when sizes exist" do
    create(:box, move:, number: "1", length_cm: 40, width_cm: 30, height_cm: 25)

    visit new_move_box_path(move)

    expect(page).to have_text(I18n.t("boxes.form.reuse_dimensions"))
    chip = find("button.ha-dim-chip", text: "40 × 30 × 25 cm")
    expect(chip["data-length"]).to eq("40")
    expect(chip["data-width"]).to eq("30")
    expect(chip["data-height"]).to eq("25")
  end

  it "is read-only for an archived move" do
    archived = create(:move, :archived, created_by: user, name: "Old Move")
    create(:box, move: archived, number: "1")

    visit move_boxes_path(archived)

    expect(page).to have_text("My Boxes")
    expect(page).to have_no_link(I18n.t("boxes.index.add"))
    expect(page).to have_no_text(I18n.t("boxes.index.start_new"))
  end
end
