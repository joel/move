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
  # Here we assert the redesigned surface: the tap-to-capture tile and the
  # photo-first panel — a succeeded photo is one card (names as chips) tapping
  # into the per-photo detail (D3).
  it "shows the tap-to-capture tile and links a succeeded photo to its detail" do
    media = create(:media, move:, box:)
    create(:recognition_run, :succeeded, move:, box:, media:)
    create(:item, move:, box:, name: "Ceramic Plates", source_media: media)

    visit move_box_capture_path(move, box)

    expect(page).to have_text("Capture for Box #001 — Kitchen")
    expect(page).to have_text(I18n.t("captures.tap_to_capture"))
    expect(page).to have_text(I18n.t("captures.session.title"))

    # The name shows as a chip inside a card that links to the photo detail.
    expect(page).to have_text("Ceramic Plates")
    expect(page).to have_link(href: move_box_review_photo_path(move, box, media_id: media.id))
  end
end
