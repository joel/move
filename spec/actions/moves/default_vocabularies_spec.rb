require "rails_helper"

RSpec.describe Moves::DefaultVocabularies do
  let(:move) { create(:move) }

  it "seeds the curated rooms" do
    described_class.apply(move)

    expect(move.rooms.pluck(:name)).to match_array(described_class::ROOMS)
  end

  it "is idempotent — re-applying creates no duplicates" do
    described_class.apply(move)
    expect { described_class.apply(move) }.not_to(change { move.rooms.count })
  end

  it "reuses a value renamed to different casing instead of colliding" do
    move.rooms.create!(name: "kitchen")

    expect { described_class.apply(move) }.not_to raise_error

    expect(move.rooms.where("LOWER(name) = ?", "kitchen").count).to eq(1)
  end
end
