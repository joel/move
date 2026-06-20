# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::Remove do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:) }

  def remove(item)
    described_class.new.call(item:, actor:)
  end

  it "soft-deletes the item and emits item.deleted with a batch id" do
    item = create(:item, :manual, move:, box:)
    allow(Rails.event).to receive(:notify)

    result = remove(item)

    expect(result).to be_success
    expect(Item.exists?(item.id)).to be(false)
    expect(Item.with_discarded.find(item.id)).to be_discarded
    expect(Rails.event).to have_received(:notify).with(
      "item.deleted", hash_including(item_id: item.id, discard_batch_id: kind_of(String))
    )
  end

  it "discards the source photo under the same batch when no other item uses it" do
    media = create(:media, move:, box:)
    item = create(:item, move:, box:, source_media: media)

    expect(remove(item)).to be_success

    discarded_media = Media.with_discarded.find(media.id)
    discarded_item = Item.with_discarded.find(item.id)
    aggregate_failures do
      expect(Media.exists?(media.id)).to be(false)
      expect(discarded_media).to be_discarded
      expect(discarded_media.discard_batch_id).to eq(discarded_item.discard_batch_id)
      expect(discarded_media.discarded_by_parent_type).to eq("Item")
      expect(discarded_media.discarded_by_parent_id).to eq(item.id)
    end
  end

  it "keeps the source photo when another kept item still references it" do
    media = create(:media, move:, box:)
    item = create(:item, move:, box:, source_media: media)
    create(:item, move:, box:, source_media: media) # sibling stays in the box

    expect(remove(item)).to be_success

    expect(Media.exists?(media.id)).to be(true)
    expect(Media.find(media.id)).not_to be_discarded
  end

  it "succeeds for a manual item with no source photo" do
    item = create(:item, :manual, move:, box:, source_media: nil)
    expect(remove(item)).to be_success
    expect(Item.exists?(item.id)).to be(false)
  end

  it "refuses to delete once the box is unpacking (use the presence transition)" do
    item = create(:item, :manual, move:, box: create(:box, move:, status: "unpacking"))

    result = remove(item)

    expect(result).to be_failure
    expect(result.failure).to eq(:wrong_phase)
    expect(Item.exists?(item.id)).to be(true)
  end
end
