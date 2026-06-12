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

  it "lists a photo's items, confirms them on view, and removes a wrong one" do
    keep = detected("Coffee machine")
    drop = detected("Glass backsplash")

    visit move_box_review_path(move, box) # enters the first photo
    expect(page).to have_field(with: "Coffee machine")

    # Reviewed-when-shown: opening the photo confirms its pending items.
    expect(keep.reload.review_state).to eq("confirmed")

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

  it "navigates from one photo to the next, then finishes at the box" do
    detected("Coffee machine")
    second = create(:media, move:, box:)
    create(:item, move:, box:, source_media: second, name: "Sofa", review_state: "pending_review")

    visit move_box_review_photo_path(move, box, media)
    expect(page).to have_text(I18n.t("reviews.photo.progress", position: 1, total: 2))

    click_link I18n.t("reviews.photo.next")
    expect(page).to have_field(with: "Sofa")

    click_link I18n.t("reviews.photo.finish")
    expect(page).to have_current_path(move_box_path(move, box))
  end
end
