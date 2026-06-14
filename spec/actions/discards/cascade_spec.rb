# frozen_string_literal: true

require "rails_helper"

# Soft-delete cascade invariants (Technical Foundation §9.3, Domain §11). Box is
# the worked example: deleting it discards its Items under one batch, and
# restoring it brings back exactly that batch — never a child discarded earlier.
RSpec.describe "Discards cascade" do # rubocop:disable RSpec/DescribeClass
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:) }

  describe Boxes::Delete do
    it "discards the box and cascades to its kept items under one batch" do
      items = create_list(:item, 2, move:, box:)

      result = described_class.new.call(box:, actor:)

      aggregate_failures do
        expect(result).to be_success
        expect(Box.exists?(box.id)).to be(false) # default scope hides it
        expect(Box.with_discarded.find(box.id)).to be_discarded
        items.each do |item|
          expect(Item.exists?(item.id)).to be(false)
          marker = Item.with_discarded.find(item.id)
          expect(marker).to be_discarded
          expect(marker.discard_batch_id).to eq(box.reload.discard_batch_id)
          expect(marker.discarded_by_parent_id).to eq(box.id)
        end
      end
    end
  end

  describe Boxes::Restore do
    it "restores the box and the items discarded by the same action" do
      items = create_list(:item, 2, move:, box:)
      Boxes::Delete.new.call(box:, actor:)
      discarded_box = Box.with_discarded.find(box.id)

      result = described_class.new.call(box: discarded_box, actor:)

      expect(result).to be_success
      expect(Box.exists?(box.id)).to be(true)
      items.each { |item| expect(Item.exists?(item.id)).to be(true) }
      expect(discarded_box.reload.discard_batch_id).to be_nil
    end

    it "does not resurrect a child discarded independently before the parent" do
      kept_item = create(:item, move:, box:)
      early_item = create(:item, move:, box:)
      # Delete one item on its own first (its own batch)...
      Items::Delete.new.call(item: early_item, actor:)
      # ...then delete the whole box.
      Boxes::Delete.new.call(box:, actor:)

      described_class.new.call(box: Box.with_discarded.find(box.id), actor:)

      expect(Item.exists?(kept_item.id)).to be(true)        # came back with the box
      expect(Item.exists?(early_item.id)).to be(false)      # stayed deleted
      expect(Item.with_discarded.find(early_item.id)).to be_discarded
    end
  end

  describe "default scope and authorization" do
    it "hides discarded rows from ordinary queries but with_discarded sees them" do
      item = create(:item, move:, box:)
      Items::Delete.new.call(item:, actor:)

      expect(Item.all).not_to include(item)
      expect(Item.with_discarded).to include(item)
    end

    it "refuses to delete on an archived (read-only) Move" do
      create(:item, move:, box:)
      move.update!(status: "archived")

      result = Boxes::Delete.new.call(box: box.reload, actor:)

      expect(result).to be_failure
      expect(Box.with_discarded.find(box.id)).not_to be_discarded
    end
  end
end
