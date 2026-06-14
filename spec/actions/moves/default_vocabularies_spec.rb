require "rails_helper"

RSpec.describe Moves::DefaultVocabularies do
  let(:move) { create(:move) }

  it "seeds the curated rooms, categories and tags" do
    described_class.apply(move)

    expect(move.rooms.pluck(:name)).to match_array(described_class::ROOMS)
    expect(move.categories.pluck(:name)).to match_array(described_class::CATEGORIES)
    expect(move.tags.pluck(:name)).to match_array(described_class::TAGS.keys)
  end

  it "assigns the correct applies_to facet to each tag" do
    described_class.apply(move)

    described_class::TAGS.each do |name, applies_to|
      expect(move.tags.find_by(name: name).applies_to).to eq(applies_to)
    end
  end

  it "is idempotent — re-applying creates no duplicates" do
    described_class.apply(move)
    expect { described_class.apply(move) }.not_to(change do
      [move.rooms.count, move.categories.count, move.tags.count]
    end)
  end
end
