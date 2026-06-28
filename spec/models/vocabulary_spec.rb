# frozen_string_literal: true

require "rails_helper"

RSpec.describe Vocabulary do
  describe ".find" do
    it "returns a vocabulary for each known kind" do
      Vocabulary::KINDS.each do |kind|
        expect(described_class.find(kind)).to be_a(described_class).and have_attributes(kind:)
      end
    end

    it "returns nil for an unknown kind (categories/tags were removed)" do
      expect(described_class.find("categories")).to be_nil
      expect(described_class.find("tags")).to be_nil
      expect(described_class.find("widgets")).to be_nil
    end
  end

  describe "kind dispatch" do
    it "maps rooms to the Room model and chip tint" do
      vocabulary = described_class.find("rooms")
      expect(vocabulary.model).to eq(Room)
      expect(vocabulary.chip_kind).to eq(:room)
      expect(vocabulary.permitted_params).to eq(%i[name])
    end
  end

  describe "#records" do
    it "returns the matching Move association" do
      move = create(:move)
      room = create(:room, move:)

      expect(described_class.find("rooms").records(move)).to include(room)
    end
  end

  describe "#usage_counts" do
    it "counts boxes per room" do
      move = create(:move)
      room = create(:room, move:)
      create(:box, move:, room:)

      expect(described_class.find("rooms").usage_counts(move)).to eq(room.id => 1)
    end
  end
end
