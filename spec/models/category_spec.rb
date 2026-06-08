# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category do
  it "has a valid factory" do
    expect(build(:category)).to be_valid
  end

  describe "validations" do
    it "requires a name" do
      expect(build(:category, name: nil)).not_to be_valid
    end

    it "enforces case-insensitive name uniqueness within a Move" do
      move = create(:move)
      create(:category, move:, name: "Kitchenware")
      expect(build(:category, move:, name: "kitchenware")).not_to be_valid
    end

    it "allows the same name in a different Move" do
      create(:category, move: create(:move), name: "Kitchenware")
      expect(build(:category, move: create(:move), name: "Kitchenware")).to be_valid
    end

    it "enforces case-insensitive uniqueness at the DB level (bypassing validation)" do
      move = create(:move)
      create(:category, move:, name: "Kitchenware")
      dup = build(:category, move:, name: "kitchenware")
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it "nullifies the category on its items when destroyed" do
    category = create(:category)
    item = create(:item, move: category.move, category:)
    category.destroy
    expect(item.reload.category_id).to be_nil
  end
end
