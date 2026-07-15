# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reviews::PendingPhotos do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:) }

  def pending_photo(box:, captured_at:)
    media = create(:media, move:, box:, captured_at:)
    create(:item, move:, box:, source_media: media, review_state: "pending_review")
    media
  end

  it "returns photos with unreviewed items oldest-first across boxes (FIFO)" do
    other_box = create(:box, move:)
    newer = pending_photo(box:, captured_at: 1.hour.ago)
    older = pending_photo(box: other_box, captured_at: 2.days.ago)

    photos = described_class.new.call(move:).value!.photos

    expect(photos.map(&:id)).to eq([older.id, newer.id])
  end

  it "counts needs_correction as pending and exposes items for grouped counts" do
    media = create(:media, move:, box:)
    create(:item, move:, box:, source_media: media, review_state: "pending_review")
    create(:item, move:, box:, source_media: media, review_state: "needs_correction")

    result = described_class.new.call(move:).value!

    expect(result.photos).to contain_exactly(media)
    expect(result.items.group(:source_media_id).count).to eq(media.id => 2)
  end

  it "excludes photos whose items are all reviewed" do
    media = create(:media, move:, box:)
    create(:item, :auto_confirmed, move:, box:, source_media: media)
    create(:item, :confirmed, move:, box:, source_media: media)

    expect(described_class.new.call(move:).value!.photos).to be_empty
  end

  it "excludes generated images and not-yet-ready captures" do
    generated = create(:media, move:, box:, captured_via: "generated")
    create(:item, move:, box:, source_media: generated, review_state: "pending_review")
    ingesting = create(:media, :pending, move:, box:)
    create(:item, move:, box:, source_media: ingesting, review_state: "pending_review")

    expect(described_class.new.call(move:).value!.photos).to be_empty
  end

  it "excludes photos in a discarded box" do
    media = pending_photo(box:, captured_at: 1.hour.ago)
    box.discard

    result = described_class.new.call(move:).value!

    expect(result.photos).not_to include(media)
  end

  it "excludes a photo whose only pending item was moved to another box (co-location)" do
    media = create(:media, move:, box:)
    create(:item, move:, box: create(:box, move:), source_media: media, review_state: "pending_review")

    expect(described_class.new.call(move:).value!.photos).to be_empty
  end

  it "excludes removed pending items (an ignored false-positive must not re-queue its photo)" do
    media = create(:media, move:, box:)
    create(:item, move:, box:, source_media: media,
                  review_state: "pending_review", presence_state: "removed")

    expect(described_class.new.call(move:).value!.photos).to be_empty
  end
end
