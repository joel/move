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
  end

  it "joins items through item_tags" do
    tag = create(:tag)
    item = create(:item, move: tag.move)
    create(:item_tag, item:, tag:)
    expect(tag.items).to include(item)
    expect(item.tags).to include(tag)
  end
end
