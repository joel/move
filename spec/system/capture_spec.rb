# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Capture image" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }
  let(:box) { create(:box, move:, number: "1", status: "packing", room: create(:room, move:, name: "Kitchen")) }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  # The capture itself auto-submits on file selection (JS), which the rack_test
  # driver can't drive — that path is covered by the request spec + /product-review.
  # Here we assert the redesigned surface: the tap-to-capture tile and the renamed
  # "Items" panel listing recognised items as tappable links to Item Detail.
  it "shows the tap-to-capture tile and links recognised items to their detail" do
    media = create(:media, move:, box:)
    create(:recognition_run, :succeeded, move:, box:, media:)
    item = create(:item, move:, box:, name: "Ceramic Plates", source_media: media)

    visit move_box_capture_path(move, box)

    expect(page).to have_text("Capture for Box #001 — Kitchen")
    expect(page).to have_text(I18n.t("captures.tap_to_capture"))
    expect(page).to have_text(I18n.t("captures.session.title")) # "Items", not "Session"

    expect(page).to have_link("Ceramic Plates", href: move_item_path(move, item))
  end
end
