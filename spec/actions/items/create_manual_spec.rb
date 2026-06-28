# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::CreateManual do
  let(:creator) { create(:user) }
  let(:move) { create(:move, created_by: creator) }
  let(:box) { create(:box, move:) }

  def call(params)
    described_class.new.call(box:, params:, creator:)
  end

  it "creates a confirmed, manual item with no source media" do
    result = call(name: "Lamp")

    expect(result).to be_success
    item = result.value!
    expect(item).to have_attributes(
      name: "Lamp", created_via: "manual",
      review_state: "confirmed", presence_state: "in_box", source_media: nil
    )
    expect(item.box).to eq(box)
  end

  it "returns validation errors for a blank name" do
    result = call(name: "")
    expect(result).to be_failure
    expect(result.failure[:name]).to be_present
  end

  context "with require_open (pure manual add / MCP)" do
    it "rejects an add to a sealed (non-packing) box" do
      sealed = create(:box, :with_room, move:, status: "sealed")
      result = described_class.new.call(box: sealed, params: { name: "Lamp" }, creator:, require_open: true)

      expect(result).to be_failure
      expect(result.failure).to eq(:not_capturable)
      expect(sealed.items).to be_empty
    end

    it "allows an add to a packing box" do
      result = described_class.new.call(box:, params: { name: "Lamp" }, creator:, require_open: true)
      expect(result).to be_success
    end

    it "does NOT gate the photo-correction callers (require_open defaults false)" do
      sealed = create(:box, :with_room, move:, status: "sealed")
      # Review / recovery add a missed item to an already-captured photo in any phase.
      result = described_class.new.call(box: sealed, params: { name: "Missed mug" }, creator:)
      expect(result).to be_success
    end
  end

  it "emits an item.created event" do
    allow(Rails.event).to receive(:notify)

    call(name: "Books")

    expect(Rails.event).to have_received(:notify).with("item.created", hash_including(:item_id))
  end
end
