require "rails_helper"

RSpec.describe Vocabularies::Remove do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:vocabulary) { Vocabulary.find("rooms") }

  it "removes a room and nullifies it on its boxes (the boxes survive)" do
    room = create(:room, move:)
    box = create(:box, move:, room:)

    result = described_class.new.call(record: room, vocabulary:, actor:)

    expect(result).to be_success
    expect(result.value!).to eq(1) # detached count
    expect(Room.exists?(room.id)).to be(false)
    expect(box.reload.room_id).to be_nil
  end

  it "reports a zero detached count for an unused value" do
    room = create(:room, move:)

    expect(described_class.new.call(record: room, vocabulary:, actor:).value!).to eq(0)
  end

  it "emits a vocabulary.removed event with the detached count" do
    allow(Rails.event).to receive(:notify)
    room = create(:room, move:)
    create(:box, move:, room:)

    described_class.new.call(record: room, vocabulary:, actor:)

    expect(Rails.event).to have_received(:notify).with(
      "vocabulary.removed", hash_including(kind: "rooms", detached_count: 1)
    )
  end
end
