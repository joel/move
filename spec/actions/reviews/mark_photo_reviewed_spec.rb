# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reviews::MarkPhotoReviewed do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }

  it "confirms the photo's unreviewed in-box items" do
    pending = create(:item, move:, box:, source_media: media, review_state: "pending_review")
    needs = create(:item, move:, box:, source_media: media, review_state: "needs_correction")

    result = described_class.new.call(media:, actor:)

    expect(result).to be_success
    expect(pending.reload.review_state).to eq("confirmed")
    expect(needs.reload.review_state).to eq("confirmed")
  end

  it "leaves auto-confirmed, removed, and other photos' items untouched" do
    auto = create(:item, :auto_confirmed, move:, box:, source_media: media)
    removed = create(:item, move:, box:, source_media: media,
                            review_state: "pending_review", presence_state: "removed")
    other = create(:item, move:, box:, review_state: "pending_review") # no source_media

    described_class.new.call(media:, actor:)

    expect(auto.reload.review_state).to eq("auto_confirmed")
    expect(removed.reload.review_state).to eq("pending_review")
    expect(other.reload.review_state).to eq("pending_review")
  end

  it "does not confirm an item that originated here but was moved to another box" do
    moved = create(:item, move:, box: create(:box, move:), source_media: media, review_state: "pending_review")

    described_class.new.call(media:, actor:)

    expect(moved.reload.review_state).to eq("pending_review")
  end

  it "leaves the linked suggestion as the AI's raw proposal (no resolution lifecycle)" do
    suggestion = create(:recognition_suggestion, :with_item, move:, box:, media:, state: "pending")

    described_class.new.call(media:, actor:)

    # The human outcome lives on the Item; the suggestion stays an immutable record.
    expect(suggestion.item.reload.review_state).to eq("confirmed")
    expect(suggestion.reload.state).to eq("pending")
  end

  it "emits item.updated per confirmed item" do
    item = create(:item, move:, box:, source_media: media, review_state: "pending_review")
    allow(Rails.event).to receive(:notify)

    described_class.new.call(media:, actor:)

    expect(Rails.event).to have_received(:notify).with("item.updated", hash_including(item_id: item.id))
  end

  it "does not mutate a read-only archived Move" do
    archived = create(:move, :archived, created_by: actor)
    archived_box = create(:box, move: archived)
    archived_media = create(:media, move: archived, box: archived_box)
    item = create(:item, move: archived, box: archived_box, source_media: archived_media,
                         review_state: "pending_review")

    result = described_class.new.call(media: archived_media, actor:)

    expect(result).to be_failure
    expect(item.reload.review_state).to eq("pending_review")
  end
end
