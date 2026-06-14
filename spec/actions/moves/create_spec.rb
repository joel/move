require "rails_helper"

RSpec.describe Moves::Create do
  let(:creator) { create(:user) }

  it "creates the move and makes the creator an admin member" do
    result = described_class.new.call(
      params: { name: "Spring Move", unit_system: "metric" },
      creator: creator
    )

    expect(result).to be_success
    move = result.value!
    expect(move.name).to eq("Spring Move")
    expect(move.created_by).to eq(creator)
    expect(move.move_memberships.find_by(user: creator)&.role).to eq("admin")
  end

  it "pre-populates the curated default categories, tags and rooms" do
    result = described_class.new.call(
      params: { name: "Spring Move", unit_system: "metric" },
      creator: creator
    )

    move = result.value!
    expect(move.rooms.count).to eq(Moves::DefaultVocabularies::ROOMS.size)
    expect(move.categories.pluck(:name)).to include("Furniture", "Kitchenware")
    expect(move.tags.count).to eq(Moves::DefaultVocabularies::TAGS.size)
    expect(move.tags.find_by(name: "Fragile")&.applies_to).to eq("box")
  end

  it "returns validation errors for an invalid move" do
    result = described_class.new.call(
      params: { name: "", unit_system: "metric" },
      creator: creator
    )

    expect(result).to be_failure
    expect(result.failure).to be_a(ActiveModel::Errors)
    expect(Move.count).to eq(0)
  end

  it "emits a move.created event" do
    allow(Rails.event).to receive(:notify)
    described_class.new.call(params: { name: "Spring Move" }, creator: creator)

    expect(Rails.event).to have_received(:notify).with("move.created", hash_including(:move_id))
  end
end
