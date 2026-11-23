# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindListEntry do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  it "enforces one pin per (move, user, item)" do
    entry = create(:find_list_entry, move:, user:)
    dupe = build(:find_list_entry, move:, user:, item: entry.item)

    expect(dupe).not_to be_valid
    expect(dupe.errors[:item_id]).to be_present
  end

  describe ".rollup_for" do
    it "orders numerically by box number (11 after 7) then item name" do
      late_box = create(:box, move:, number: "11")
      early_box = create(:box, move:, number: "7")
      create(:find_list_entry, move:, user:, item: create(:item, move:, box: late_box, name: "Lamp"))
      create(:find_list_entry, move:, user:, item: create(:item, move:, box: early_box, name: "Mug"))
      create(:find_list_entry, move:, user:, item: create(:item, move:, box: early_box, name: "Bowl"))

      names = described_class.rollup_for(move, user).map { |entry| entry.item.name }

      expect(names).to eq(%w[Bowl Mug Lamp])
    end

    it "drops entries whose item was soft-deleted and other users' rows" do
      other_user = create(:user)
      box = create(:box, move:)
      kept = create(:find_list_entry, move:, user:, item: create(:item, move:, box:, name: "Kept"))
      discarded_item = create(:item, move:, box:, name: "Gone")
      create(:find_list_entry, move:, user:, item: discarded_item)
      create(:find_list_entry, move:, user: other_user, item: create(:item, move:, box:, name: "Theirs"))
      discarded_item.discard!

      expect(described_class.rollup_for(move, user)).to contain_exactly(kept)
    end
  end

  describe ".snapshot_for" do
    it "returns the rollup rows, each carrying the DB-counted kept-only total (#873)" do
      box = create(:box, move:)
      create(:find_list_entry, move:, user:, item: create(:item, move:, box:, name: "Mug"))
      create(:find_list_entry, move:, user:, item: create(:item, move:, box:, name: "Bowl"))
      gone = create(:item, move:, box:, name: "Gone")
      create(:find_list_entry, move:, user:, item: gone)
      create(:find_list_entry, move:, user: create(:user), item: create(:item, move:, box:))
      gone.discard!

      snapshot = described_class.snapshot_for(move, user)

      expect(snapshot.map { |entry| entry.item.name }).to eq(%w[Bowl Mug])
      expect(snapshot.map(&:pinned_total)).to eq([2, 2])
    end

    it "is empty when nothing is pinned" do
      expect(described_class.snapshot_for(move, user)).to eq([])
    end
  end

  describe "one live-pin definition (#894)" do
    # An item kept inside a discarded box. Items::Restore now refuses to create
    # this, so it is built directly: the counts must agree regardless.
    def kept_item_in_discarded_box
      box = create(:box, move:)
      item = create(:item, move:, box:, name: "Orphan")
      box.discard_in_batch!(batch_id: SecureRandom.uuid, parent: nil)
      item
    end

    it "counts the same pins in pinned_item_ids_for and snapshot_for" do
      live_box = create(:box, move:)
      live = create(:item, move:, box: live_box, name: "Mug")
      create(:find_list_entry, move:, user:, item: live)
      create(:find_list_entry, move:, user:, item: kept_item_in_discarded_box)
      gone = create(:item, move:, box: live_box, name: "Gone")
      create(:find_list_entry, move:, user:, item: gone)
      gone.discard!

      ids = described_class.pinned_item_ids_for(move:, user:)
      snapshot = described_class.snapshot_for(move, user)

      aggregate_failures do
        expect(ids).to eq(Set[live.id])
        expect(snapshot.map(&:item_id)).to eq([live.id])
        expect(snapshot.first.pinned_total).to eq(ids.size)
      end
    end
  end
end
