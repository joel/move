# frozen_string_literal: true

require "rails_helper"

RSpec.describe Photos::Delete do
  let(:move) { create(:move) }
  let(:box) { create(:box, move:) } # packing by default
  let(:media) { create(:media, move:, box:) }
  let(:actor) { create(:user) }

  def call(photo: media)
    described_class.new.call(media: photo, actor:)
  end

  it "soft-deletes the photo and every item it sourced under one discard batch" do
    a = create(:item, move:, box:, source_media: media)
    b = create(:item, move:, box:, source_media: media)

    expect(call).to be_success

    expect(Media.kept.exists?(media.id)).to be(false)
    expect(Item.kept.where(id: [a.id, b.id])).to be_empty
    batch = Media.with_discarded.find(media.id).discard_batch_id
    expect(batch).to be_present
    # the items joined the SAME batch, parented by the photo (so one restore returns all)
    expect(Item.with_discarded.where(id: [a.id, b.id]).pluck(:discard_batch_id).uniq).to eq([batch])
    expect(Item.with_discarded.where(id: a.id).pick(:discarded_by_parent_type)).to eq("Media")
  end

  it "emits media.discarded with the batch id" do
    allow(Rails.event).to receive(:notify).and_call_original

    call

    expect(Rails.event).to have_received(:notify)
      .with("media.discarded", hash_including(media_id: media.id, move_id: move.id, discard_batch_id: be_present))
  end

  it "refuses on a non-packing box and discards nothing" do
    sealed = create(:box, :sealed, move:)
    photo = create(:media, move:, box: sealed)
    item = create(:item, move:, box: sealed, source_media: photo)

    result = call(photo:)
    expect(result).to be_failure
    expect(result.failure).to eq(:wrong_phase)

    expect(Media.kept.exists?(photo.id)).to be(true)
    expect(Item.kept.exists?(item.id)).to be(true)
  end

  it "restores the photo and its items together (Photos::Restore)" do
    item = create(:item, move:, box:, source_media: media)
    call

    expect(Photos::Restore.new.call(media: Media.with_discarded.find(media.id), actor:)).to be_success

    expect(Media.kept.exists?(media.id)).to be(true)
    expect(Item.kept.exists?(item.id)).to be(true)
  end
end
