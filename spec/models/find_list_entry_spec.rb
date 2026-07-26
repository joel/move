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
end
