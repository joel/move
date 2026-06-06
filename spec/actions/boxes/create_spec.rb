require "rails_helper"

RSpec.describe Boxes::Create do
  let(:creator) { create(:user) }
  let(:move) { create(:move, created_by: creator) }

  it "creates a box with an auto-assigned number and a permanent qr_token" do
    result = described_class.new.call(move:, params: {}, creator:)

    expect(result).to be_success
    box = result.value!
    expect(box.number).to eq("1")
    expect(box.qr_token).to be_present
    expect(box.move).to eq(move)
  end

  it "assigns sequential numbers per move" do
    create(:box, move:, number: "1")
    create(:box, move:, number: "2")

    box = described_class.new.call(move:, params: {}, creator:).value!
    expect(box.number).to eq("3")
  end

  it "honours an explicit number override" do
    box = described_class.new.call(move:, params: { number: "7" }, creator:).value!
    expect(box.number).to eq("7")
  end

  it "find-or-creates a room by name (case-insensitive) and attaches it" do
    create(:room, move:, name: "Kitchen")

    box = described_class.new.call(move:, params: { room_name: "kitchen" }, creator:).value!

    expect(box.room.name).to eq("Kitchen")
    expect(move.rooms.count).to eq(1)
  end

  it "stores optional dimensions" do
    box = described_class.new.call(
      move:, params: { length_cm: 40, width_cm: 30, height_cm: 25 }, creator:
    ).value!

    expect(box).not_to be_missing_dimensions
  end

  it "returns validation errors for a non-numeric number override" do
    result = described_class.new.call(move:, params: { number: "A1" }, creator:)

    expect(result).to be_failure
    expect(result.failure).to be_a(ActiveModel::Errors)
    expect(move.boxes.count).to eq(0)
  end

  it "does not create an orphan room when the box is invalid" do
    expect do
      described_class.new.call(move:, params: { number: "A1", room_name: "Attic" }, creator:)
    end.not_to change(move.rooms, :count)
  end

  it "emits a box.created event" do
    allow(Rails.event).to receive(:notify)
    described_class.new.call(move:, params: {}, creator:)

    expect(Rails.event).to have_received(:notify).with(
      "box.created", hash_including(:box_id, :move_id)
    )
  end
end
