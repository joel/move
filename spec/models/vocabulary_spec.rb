# frozen_string_literal: true

require "rails_helper"

RSpec.describe Vocabulary do
  describe ".find" do
    it "returns a vocabulary for each known kind" do
      Vocabulary::KINDS.each do |kind|
        expect(described_class.find(kind)).to be_a(described_class).and have_attributes(kind:)
      end
    end

    it "returns nil for an unknown kind" do
      expect(described_class.find("widgets")).to be_nil
    end
  end

  describe "kind dispatch" do
    it "maps categories to the Category model and chip tint" do
      vocabulary = described_class.find("categories")
      expect(vocabulary.model).to eq(Category)
      expect(vocabulary.chip_kind).to eq(:category)
      expect(vocabulary.applies_to?).to be(false)
      expect(vocabulary.permitted_params).to eq(%i[name])
    end

    it "marks only tags as carrying the applies_to facet" do
      vocabulary = described_class.find("tags")
      expect(vocabulary.model).to eq(Tag)
      expect(vocabulary.applies_to?).to be(true)
      expect(vocabulary.permitted_params).to eq(%i[name applies_to])
    end

    it "maps rooms to the Room model" do
      expect(described_class.find("rooms").model).to eq(Room)
    end
  end

  describe "#records" do
    it "returns the matching Move association" do
      move = create(:move)
      category = create(:category, move:)

      expect(described_class.find("categories").records(move)).to include(category)
    end
  end

  describe "#usage_counts" do
    let(:move) { create(:move) }

    it "counts items per category" do
      category = create(:category, move:)
      create_list(:item, 2, move:, category:)

      expect(described_class.find("categories").usage_counts(move)).to eq(category.id => 2)
    end

    it "counts boxes per room" do
      room = create(:room, move:)
      create(:box, move:, room:)

      expect(described_class.find("rooms").usage_counts(move)).to eq(room.id => 1)
    end

    it "counts items per tag through the join" do
      tag = create(:tag, move:)
      item = create(:item, move:)
      create(:item_tag, item:, tag:)

      expect(described_class.find("tags").usage_counts(move)).to eq(tag.id => 1)
    end
  end
end
