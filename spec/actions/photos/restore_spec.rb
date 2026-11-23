# frozen_string_literal: true

require "rails_helper"

RSpec.describe Photos::Restore do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }
  let!(:item) { create(:item, move:, box:, source_media: media) }

  def restore
    described_class.new.call(media: Media.with_discarded.find(media.id), actor:)
  end

  before do
    FindLists::Pin.new.call(move:, user: actor, item:)
    Photos::Delete.new.call(media:, actor:)
  end

  it "restores the photo and the items deleted with it" do
    expect(restore).to be_success
    expect(Media.exists?(media.id)).to be(true)
    expect(Item.exists?(item.id)).to be(true)
  end

  # #894 — the photo was deleted BEFORE its box, so the box's cascade left it
  # out; restoring it alone would revive it and its items inside a deleted box.
  context "when its box was deleted afterwards" do
    before { Boxes::Delete.new.call(box:, actor:) }

    it "refuses and leaves the photo and its items deleted" do
      aggregate_failures do
        expect(restore).to eq(Dry::Monads::Failure(:parent_discarded))
        expect(Media.with_discarded.find(media.id)).to be_discarded
        expect(Item.with_discarded.find(item.id)).to be_discarded
        expect(FindListEntry.pinned_item_ids_for(move:, user: actor)).to be_empty
      end
    end

    it "restores once the box is restored first" do
      Boxes::Restore.new.call(box: Box.with_discarded.find(box.id), actor:)

      expect(restore).to be_success
      expect(Item.exists?(item.id)).to be(true)
    end
  end
end
