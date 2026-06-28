require "rails_helper"

RSpec.describe Vocabularies::Update do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:vocabulary) { Vocabulary.find("rooms") }

  it "renames a value and the rename propagates to associated records" do
    room = create(:room, move:, name: "Kitchn")
    box = create(:box, move:, room:)

    result = described_class.new.call(record: room, vocabulary:, params: { name: "Kitchen" }, actor:)

    expect(result).to be_success
    expect(room.reload.name).to eq("Kitchen")
    expect(box.reload.room.name).to eq("Kitchen")
  end

  it "returns validation errors for a blank name" do
    room = create(:room, move:)

    result = described_class.new.call(record: room, vocabulary:, params: { name: "" }, actor:)

    expect(result).to be_failure
    expect(result.failure).to be_a(ActiveModel::Errors)
  end

  it "emits a vocabulary.updated event" do
    allow(Rails.event).to receive(:notify)
    room = create(:room, move:)

    described_class.new.call(record: room, vocabulary:, params: { name: "Renamed" }, actor:)

    expect(Rails.event).to have_received(:notify).with(
      "vocabulary.updated", hash_including(kind: "rooms", record_id: room.id)
    )
  end
end
