# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Move-wide review queue flow" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }
  let(:kitchen_box) { create(:box, move:, number: "1", room: create(:room, move:, name: "Kitchen")) }
  let(:office_box) { create(:box, move:, number: "2", room: create(:room, move:, name: "Office")) }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  def pending_photo(box:, name:, captured_at:)
    photo = create(:media, move:, box:, captured_at:)
    create(:item, move:, box:, source_media: photo, name:, review_state: "pending_review")
    photo
  end

  it "lists both boxes' photos and opens the newest one via Review all, confirming it" do
    pending_photo(box: kitchen_box, name: "Coffee machine", captured_at: 2.hours.ago)
    pending_photo(box: office_box, name: "Desk lamp", captured_at: 1.hour.ago)

    visit move_review_path(move)
    expect(page).to have_text("Box 1").and have_text("Kitchen")
    expect(page).to have_text("Box 2").and have_text("Office")

    # Newest first (#687): Review all enters the Office photo, located by its badge.
    click_link I18n.t("review_queues.show.review_all")
    expect(page).to have_field(with: "Desk lamp")
    expect(page).to have_text(I18n.t("reviews.photo.queue_badge", number: "2"))

    # #660 — opening no longer confirms; the queue clears only via explicit marks.
    expect(move.items.find_by(name: "Desk lamp").review_state).to eq("pending_review")
  end

  it "marks across the box boundary, then finishes at the caught-up queue" do
    pending_photo(box: kitchen_box, name: "Coffee machine", captured_at: 2.hours.ago)
    pending_photo(box: office_box, name: "Desk lamp", captured_at: 1.hour.ago)

    visit move_review_path(move)
    click_link I18n.t("review_queues.show.review_all")

    # Mark as Reviewed crosses from the Office box into the Kitchen photo
    # (top + bottom controls → match: :first picks the header one).
    click_button I18n.t("reviews.photo.mark_reviewed"), match: :first
    expect(page).to have_field(with: "Coffee machine")
    expect(page).to have_text(I18n.t("reviews.photo.queue_badge", number: "1"))

    # Marking the last photo returns to the queue, now all caught up.
    click_button I18n.t("reviews.photo.mark_reviewed"), match: :first
    expect(page).to have_current_path(move_review_path(move))
    expect(page).to have_text(I18n.t("review_queues.show.empty.caught_up_title"))
  end

  it "walks the queue with Ignore, leaving every photo pending" do
    pending_photo(box: kitchen_box, name: "Coffee machine", captured_at: 2.hours.ago)
    pending_photo(box: office_box, name: "Desk lamp", captured_at: 1.hour.ago)

    visit move_review_path(move)
    click_link I18n.t("review_queues.show.review_all")

    click_link I18n.t("reviews.photo.ignore"), match: :first
    expect(page).to have_field(with: "Coffee machine")

    # Ignoring the last photo exits to the queue — which still lists both photos.
    click_link I18n.t("reviews.photo.ignore"), match: :first
    expect(page).to have_current_path(move_review_path(move))
    expect(page).to have_text("Box 1").and have_text("Box 2")
    expect(move.items.where(review_state: "pending_review").count).to eq(2)
  end

  it "reaches the queue from the Menu hub row and hides the badge once clear" do
    pending_photo(box: kitchen_box, name: "Coffee machine", captured_at: 1.hour.ago)

    visit move_menu_path(move)
    click_link I18n.t("menu.show.review")

    expect(page).to have_current_path(move_review_path(move))
    expect(page).to have_text(I18n.t("review_queues.show.pending_badge", count: 1))
  end
end
