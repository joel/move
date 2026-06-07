# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Recognition review" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET .../review (queue)" do
    it "renders the queue with summary counts and unresolved suggestions" do
      create(:recognition_suggestion, :with_item, move:, box:, proposed_name: "Lamp")

      get move_box_review_index_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("reviews.queue.title")).and include("Lamp")
    end
  end

  describe "GET .../review/:id (item-by-item)" do
    it "renders one suggestion with progress" do
      suggestion = create(:recognition_suggestion, :with_item, move:, box:, proposed_name: "Chair")

      get move_box_review_path(move, box, suggestion)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Chair").and include(I18n.t("reviews.actions.keep"))
    end
  end

  describe "PATCH keep" do
    it "accepts the suggestion, confirms the item, advances" do
      suggestion = create(:recognition_suggestion, :with_item, move:, box:)

      patch keep_move_box_review_path(move, box, suggestion)

      expect(suggestion.reload.state).to eq("accepted")
      expect(suggestion.item.review_state).to eq("confirmed")
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH correct" do
    it "marks corrected and redirects to the item edit" do
      suggestion = create(:recognition_suggestion, :with_item, move:, box:)

      patch correct_move_box_review_path(move, box, suggestion)

      expect(suggestion.reload.state).to eq("corrected")
      expect(response).to redirect_to(move_item_path(move, suggestion.item, review_box_id: box.id))
    end
  end

  describe "PATCH mark_false_positive" do
    it "marks false_positive and removes the item from inventory" do
      suggestion = create(:recognition_suggestion, :with_item, move:, box:)

      patch mark_false_positive_move_box_review_path(move, box, suggestion)

      expect(suggestion.reload.state).to eq("false_positive")
      expect(suggestion.item.presence_state).to eq("removed")
    end
  end

  describe "archived Move (viewer cannot mutate)" do
    let(:move) { create(:move, :archived, created_by: user) }

    it "redirects a keep attempt without resolving" do
      suggestion = create(:recognition_suggestion, :with_item, move:, box:)

      patch keep_move_box_review_path(move, box, suggestion)

      expect(suggestion.reload.state).to eq("pending")
      expect(response).to redirect_to(move_box_review_index_path(move, box))
    end
  end
end
