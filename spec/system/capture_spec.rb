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

  # The in-app viewfinder (#616) is progressive enhancement driven by the
  # camera-capture controller, so rack_test asserts the scaffolding is all
  # present (visible: :all — the hidden-by-default class is CSS, which rack_test
  # cannot evaluate); the live behaviour is covered by /product-review.
  it "renders the viewfinder scaffolding with the tile as the no-camera fallback" do
    visit move_box_capture_path(move, box)

    expect(page).to have_css(
      "[data-controller='camera-capture'] [data-camera-capture-target='viewfinder'] video",
      visible: :all
    )
    expect(page).to have_css(
      "button[aria-label='#{I18n.t("captures.viewfinder.shutter")}'][disabled]", visible: :all
    )
    expect(page).to have_button(I18n.t("captures.viewfinder.use_camera"), visible: :all)
    expect(page).to have_button(I18n.t("captures.viewfinder.library"), visible: :all)
    expect(page).to have_text(I18n.t("captures.viewfinder.unavailable"))

    # The tile stays the no-camera capture affordance — now an OS chooser:
    # the input must carry both controllers' targets and no `capture` attribute.
    expect(page).to have_css(
      "input[type='file'][accept='image/*'][data-capture-upload-target='file']" \
      "[data-camera-capture-target='input']:not([capture])",
      visible: :all
    )
  end

  # The upload lock's lifecycle wiring (#620): `change` raises it,
  # turbo:submit-start cancels the pre-submit failsafe (a submit-end is then
  # guaranteed, so the lock holds through arbitrarily slow submissions), and
  # turbo:submit-end releases it.
  it "wires the upload lock to the full submission lifecycle" do
    visit move_box_capture_path(move, box)

    expect(page).to have_css(
      "[data-controller='camera-capture'][data-action*='change->camera-capture#uploadStarted']" \
      "[data-action*='turbo:submit-start->camera-capture#uploadInFlight']" \
      "[data-action*='turbo:submit-end->camera-capture#uploadSettled']"
    )
  end
end
