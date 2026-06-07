# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Recognition review flow" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }
  let(:box) { create(:box, move:, number: "1", room: create(:room, move:, name: "Kitchen")) }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  it "starts the queue and keeps a suggestion, confirming its item" do
    suggestion = create(:recognition_suggestion, :with_item, move:, box:, proposed_name: "Toaster", confidence_score: 0.4)

    visit move_box_review_index_path(move, box)
    expect(page).to have_text("Toaster")
    click_link I18n.t("reviews.queue.start")

    click_button I18n.t("reviews.actions.keep")
    expect(suggestion.reload.state).to eq("accepted")
    expect(suggestion.item.review_state).to eq("confirmed")
  end

  it "marks a detection as a false positive (leaves inventory)" do
    suggestion = create(:recognition_suggestion, :with_item, move:, box:, proposed_name: "Glare")

    visit move_box_review_path(move, box, suggestion)
    click_button I18n.t("reviews.actions.ignore")

    expect(suggestion.reload.state).to eq("false_positive")
    expect(suggestion.item.presence_state).to eq("removed")
  end

  it "routes Correct to the item edit screen" do
    suggestion = create(:recognition_suggestion, :with_item, move:, box:, proposed_name: "Kettle")

    visit move_box_review_path(move, box, suggestion)
    click_button I18n.t("reviews.actions.correct")

    expect(page).to have_text(I18n.t("items.show.title"))
    expect(suggestion.reload.state).to eq("corrected")
  end
end
