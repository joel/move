# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tag do
  it "has a valid factory" do
    expect(build(:tag)).to be_valid
  end

  describe "validations" do
    it "requires a name" do
      expect(build(:tag, name: nil)).not_to be_valid
    end

    it "enforces case-insensitive name uniqueness within a Move" do
      move = create(:move)
      create(:tag, move:, name: "Heavy")
      expect(build(:tag, move:, name: "heavy")).not_to be_valid
    end

    it "defaults applies_to to item and rejects unknown values" do
      expect(create(:tag).applies_to).to eq("item")
      expect(build(:tag, applies_to: "bogus")).not_to be_valid
      expect(build(:tag, :both)).to be_valid
    end

    it "enforces case-insensitive uniqueness at the DB level (bypassing validation)" do
      move = create(:move)
      create(:tag, move:, name: "Heavy")
      dup = build(:tag, move:, name: "heavy")
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe ".for_items" do
    it "includes item and both tags but excludes box-only tags" do
      move = create(:move)
      item_tag = create(:tag, move:, name: "Heavy")
      both_tag = create(:tag, :both, move:, name: "Important")
      box_tag = create(:tag, :box, move:, name: "Sealed")

      expect(move.tags.for_items).to contain_exactly(item_tag, both_tag)
      expect(move.tags.for_items).not_to include(box_tag)
    end
  end

  it "joins items through item_tags" do
    tag = create(:tag)
    item = create(:item, move: tag.move)
    create(:item_tag, item:, tag:)
    expect(tag.items).to include(item)
    expect(item.tags).to include(tag)
  end

  describe ".by_usage" do
    it "orders most-used first, then alphabetically, keeping unused tags (last)" do
      move = create(:move)
      popular = create(:tag, move:, name: "Fragile") # 3 items
      rare = create(:tag, move:, name: "Books")        # 1 item
      create(:tag, move:, name: "Bulky")               # 0 items
      create(:tag, move:, name: "Awkward")             # 0 items

      3.times { create(:item_tag, tag: popular, item: create(:item, move:)) }
      create(:item_tag, tag: rare, item: create(:item, move:))

      expect(move.tags.by_usage.map(&:name)).to eq(%w[Fragile Books Awkward Bulky])
    end
  end
end
