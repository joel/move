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

  it "captures an image and lands recognized items (fake provider)" do
    visit move_box_capture_path(move, box)
    expect(page).to have_text("Capture for Box #001 — Kitchen")

    attach_file("file", Rails.root.join("spec/fixtures/files/sample_image.png"))
    click_button I18n.t("captures.shutter")

    # :inline recognition runs during the request, so the session shows the result.
    expect(page).to have_current_path(move_box_capture_path(move, box), ignore_query: true)
    expect(page).to have_text(I18n.t("ui.states.succeeded"))
    # One photo → many items: the session reflects the detection count, not 1:1.
    expect(page).to have_text(I18n.t("captures.session.items_found", count: 3))
    expect(box.items.count).to eq(3)
    expect(box.items.where(review_state: "auto_confirmed").count).to eq(2)
  end
end
