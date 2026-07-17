# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Per-photo review flow" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }
  let(:box) { create(:box, move:, number: "1", room: create(:room, move:, name: "Kitchen")) }
  let(:media) { create(:media, move:, box:) }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  def detected(name, **attrs)
    create(:item, move:, box:, source_media: media, name:, review_state: "pending_review", **attrs)
  end

  it "lists a photo's items without changing state, and removes a wrong one" do
    keep = detected("Coffee machine")
    drop = detected("Glass backsplash")

    visit move_box_review_path(move, box) # enters the first photo
    expect(page).to have_field(with: "Coffee machine")

    # #660 — reviewing is explicit: opening the photo confirms nothing.
    expect(keep.reload.review_state).to eq("pending_review")

    click_button I18n.t("reviews.photo.remove_named", name: "Glass backsplash")
    expect(drop.reload.presence_state).to eq("removed")
    expect(page).to have_no_field(with: "Glass backsplash")
  end

  it "adds a missed item to the photo" do
    detected("Coffee machine")

    visit move_box_review_photo_path(move, box, media)
    fill_in placeholder: I18n.t("reviews.photo.add_placeholder"), with: "Cutting board"
    click_button I18n.t("reviews.photo.add")

    expect(box.items.find_by(name: "Cutting board")).to have_attributes(
      created_via: "manual", source_media_id: media.id
    )
    expect(page).to have_field(with: "Cutting board")
  end

  # #660 — the pair renders at the header AND the footer, so clicks use
  # match: :first (the top control, the one long lists used to bury).
  it "marks the first photo reviewed, ignores the second, and lands at the box" do
    first_item = detected("Coffee machine")
    second = create(:media, move:, box:)
    second_item = create(:item, move:, box:, source_media: second, name: "Sofa", review_state: "pending_review")

    visit move_box_review_photo_path(move, box, media)
    expect(page).to have_text(I18n.t("reviews.photo.progress", position: 1, total: 2))

    click_button I18n.t("reviews.photo.mark_reviewed"), match: :first
    expect(page).to have_field(with: "Sofa")
    expect(first_item.reload.review_state).to eq("confirmed")

    # Ignore advances without confirming; on the last photo it exits to the box.
    click_link I18n.t("reviews.photo.ignore"), match: :first
    expect(page).to have_current_path(move_box_path(move, box))
    expect(second_item.reload.review_state).to eq("pending_review")
  end
end
