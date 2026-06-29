# frozen_string_literal: true

require "rails_helper"

RSpec.describe Item do
  it "has a valid factory" do
    expect(build(:item)).to be_valid
  end

  it "validates name and the state enums" do
    item = build(:item, name: nil, review_state: "bogus", presence_state: "nowhere")
    expect(item).not_to be_valid
    expect(item.errors.attribute_names).to include(:name, :review_state, :presence_state)
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

  describe "image generation claim (#416)" do
    let(:item) { create(:item, :manual) }

    it "claims a free, photo-less item exactly once under contention (others get nil)" do
      results = Array.new(3) { item.claim_image_generation! }
      expect(results.compact.size).to eq(1) # one timestamp token, the rest nil
      expect(item.reload.image_generating_at).to be_present
    end

    it "refuses to claim an item that already has a photo (nil token)" do
      item.update!(source_media: create(:media, move: item.move, box: item.box))
      expect(item.claim_image_generation!).to be_nil
    end

    it "reclaims an abandoned (stale) claim so a crashed job self-heals (returns a token)" do
      item.update!(image_generating_at: (Item::IMAGE_CLAIM_TTL + 1.minute).ago)
      expect(item.claim_image_generation!).to be_present
    end

    it "holds_image_claim? matches only the exact (second-precision) token" do
      token = item.claim_image_generation!
      expect(item.reload).to be_holds_image_claim(token)
      expect(item).not_to be_holds_image_claim(5.minutes.from_now)
    end

    it "reports a fresh claim as generating, a stale one as not" do
      item.update!(image_generating_at: Time.current)
      expect(item).to be_image_generating
      item.update!(image_generating_at: (Item::IMAGE_CLAIM_TTL + 1.minute).ago)
      expect(item).not_to be_image_generating
    end
  end
end
