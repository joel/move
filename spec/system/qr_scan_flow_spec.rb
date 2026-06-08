# frozen_string_literal: true

require "rails_helper"

# E2/E1 user journey. The live camera (getUserMedia + jsQR) needs a real browser
# and camera, so these cover the no-JS-reachable surface: the scanner page chrome
# + manual-entry affordance, token resolution states, and the label/manifest
# entry points. Camera decoding itself is verified live in /product-review.
RSpec.describe "QR scan & labels" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  it "shows the scanner page and resolves a token without changing box status" do
    box = create(:box, :with_room, move:, number: "3", status: "sealed", qr_token: "tok-sys")

    visit move_scan_path(move)
    expect(page).to have_text(I18n.t("scans.show.aim"))
    expect(page).to have_field("token") # manual-entry fallback

    visit move_scan_resolve_path(move, "tok-sys")
    expect(page).to have_text("Box #003")
    expect(page).to have_text(I18n.t("scans.resolved.success"))

    click_link I18n.t("scans.resolved.open")
    expect(page).to have_text("Box #003") # box detail
    expect(box.reload.status).to eq("sealed")
  end

  it "offers label and manifest print actions on the box detail" do
    box = create(:box, :with_room, move:, number: "4")

    visit move_box_path(move, box)

    expect(page).to have_link(
      I18n.t("boxes.actions.print_label"), href: move_box_label_path(move, box)
    )
    expect(page).to have_link(
      I18n.t("boxes.actions.print_manifest"), href: move_box_manifest_path(move, box)
    )
  end
end
