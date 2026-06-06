require "rails_helper"

RSpec.describe Boxes::Update do
  let(:editor) { create(:user) }
  let(:move) { create(:move, created_by: editor) }
  let(:box) { create(:box, move:, number: "1") }

  it "updates dimensions and weight" do
    result = described_class.new.call(
      box:, params: { length_cm: 40, width_cm: 30, height_cm: 25, weight_kg: 8 }, editor:
    )

    expect(result).to be_success
    expect(box.reload).to have_attributes(length_cm: 40, weight_kg: 8)
    expect(box).not_to be_missing_dimensions
  end

  it "resolves a room by name (case-insensitive find-or-create)" do
    create(:room, move:, name: "Kitchen")

    described_class.new.call(box:, params: { room_name: "kitchen" }, editor:)

    expect(box.reload.room.name).to eq("Kitchen")
    expect(move.rooms.count).to eq(1)
  end

  it "leaves the existing room untouched when room_name is blank" do
    kitchen = create(:room, move:, name: "Kitchen")
    box.update!(room: kitchen)

    described_class.new.call(box:, params: { weight_kg: 5, room_name: "" }, editor:)

    expect(box.reload.room).to eq(kitchen)
  end

  it "returns validation errors for an invalid number" do
    result = described_class.new.call(box:, params: { number: "A1" }, editor:)

    expect(result).to be_failure
    expect(result.failure).to be_a(ActiveModel::Errors)
    expect(box.reload.number).to eq("1")
  end

  it "emits a box.updated event" do
    allow(Rails.event).to receive(:notify)
    described_class.new.call(box:, params: { weight_kg: 3 }, editor:)

    expect(Rails.event).to have_received(:notify).with("box.updated", hash_including(:box_id))
  end
end
