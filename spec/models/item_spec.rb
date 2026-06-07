# frozen_string_literal: true

require "rails_helper"

RSpec.describe Item do
  it "has a valid factory" do
    expect(build(:item)).to be_valid
  end

  it "validates name, quantity and the state enums" do
    item = build(:item, name: nil, quantity: 0, review_state: "bogus", presence_state: "nowhere")
    expect(item).not_to be_valid
    expect(item.errors.attribute_names).to include(:name, :quantity, :review_state, :presence_state)
  end

  describe "scopes" do
    it "filters in-box and pending-review items" do
      move = create(:move)
      box = create(:box, move:)
      create(:item, move:, box:, review_state: "pending_review")
      create(:item, :auto_confirmed, move:, box:)
      create(:item, :confirmed, move:, box:, presence_state: "removed")

      expect(box.items.in_box.count).to eq(2)
      expect(box.items.pending_review.count).to eq(1)
      expect(box.item_count).to eq(2)
      expect(box.pending_review_count).to eq(1)
    end

    it "excludes removed items from pending_review (e.g. ignored false-positives)" do
      box = create(:box)
      kept = create(:item, move: box.move, box:, review_state: "pending_review")
      create(:item, move: box.move, box:, review_state: "pending_review", presence_state: "removed")

      expect(box.items.pending_review).to contain_exactly(kept)
    end
  end
end
