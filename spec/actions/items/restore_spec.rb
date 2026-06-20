# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::Restore do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:) }

  def restore(item)
    described_class.new.call(item:, actor:)
  end

  it "un-discards the item and the photo deleted with it in the same batch" do
    media = create(:media, move:, box:)
    item = create(:item, move:, box:, source_media: media)
    Items::Remove.new.call(item:, actor:)

    result = restore(Item.with_discarded.find(item.id))

    aggregate_failures do
      expect(result).to be_success
      expect(Item.exists?(item.id)).to be(true)
      expect(Media.exists?(media.id)).to be(true)
      expect(Media.find(media.id)).not_to be_discarded
    end
  end

  it "restores a shared photo when bringing back any item that references it" do
    media = create(:media, move:, box:)
    first = create(:item, move:, box:, source_media: media)
    second = create(:item, move:, box:, source_media: media)
    Items::Remove.new.call(item: first, actor:)  # photo kept — second still uses it
    Items::Remove.new.call(item: second, actor:) # photo now discarded (second's batch)

    restore(Item.with_discarded.find(first.id))  # restore the FIRST item, not the second

    # The photo comes back because first now references it again, even though it
    # was discarded under the second item's batch.
    expect(Media.exists?(media.id)).to be(true)
    expect(Media.find(media.id)).not_to be_discarded
  end

  it "leaves a photo discarded independently for another reason alone" do
    media = create(:media, move:, box:)
    item = create(:item, :manual, move:, box:, source_media: nil)
    media.discard_in_batch!(batch_id: SecureRandom.uuid, parent: nil) # unrelated delete
    Items::Remove.new.call(item:, actor:)

    restore(Item.with_discarded.find(item.id))

    expect(Media.exists?(media.id)).to be(false)
    expect(Media.with_discarded.find(media.id)).to be_discarded
  end
end
