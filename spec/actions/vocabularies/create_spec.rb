require "rails_helper"

RSpec.describe Vocabularies::Create do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:vocabulary) { Vocabulary.find("rooms") }

  it "adds a room by name" do
    result = described_class.new.call(move:, vocabulary:, params: { name: "Attic" }, actor:)

    expect(result).to be_success
    expect(result.value!).to be_a(Room).and have_attributes(name: "Attic", move:)
  end

  it "ignores unpermitted params (rooms accept only a name)" do
    room = described_class.new.call(
      move:, vocabulary:, params: { name: "Garage", applies_to: "both" }, actor:
    ).value!

    expect(room).to be_a(Room)
    expect(room).not_to respond_to(:applies_to)
  end

  it "returns validation errors for a blank name" do
    result = described_class.new.call(move:, vocabulary:, params: { name: "" }, actor:)

    expect(result).to be_failure
    expect(result.failure).to be_a(ActiveModel::Errors)
    expect(move.rooms.count).to eq(0)
  end

  it "rejects a case-variant duplicate" do
    create(:room, move:, name: "Kitchen")

    result = described_class.new.call(move:, vocabulary:, params: { name: "kitchen" }, actor:)

    expect(result).to be_failure
  end

  it "surfaces a unique-index race as a taken name, not a 500" do
    relation = move.rooms
    record = build(:room, move:, name: "Kitchen")
    allow(record).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)
    allow(vocabulary).to receive(:records).with(move).and_return(relation)
    allow(relation).to receive(:new).and_return(record)

    result = described_class.new.call(move:, vocabulary:, params: { name: "Kitchen" }, actor:)

    expect(result).to be_failure
    expect(result.failure).to be_a(ActiveModel::Errors)
    expect(result.failure[:name]).to be_present
  end

  it "emits a vocabulary.created event" do
    allow(Rails.event).to receive(:notify)

    described_class.new.call(move:, vocabulary:, params: { name: "Attic" }, actor:)

    expect(Rails.event).to have_received(:notify).with(
      "vocabulary.created", hash_including(kind: "rooms", move_id: move.id)
    )
  end
end
