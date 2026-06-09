# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::VolumeSummary do
  let(:move) { create(:move) }
  let(:actor) { move.created_by }

  def box(room:, dims: nil, weight: nil)
    length, width, height = dims
    create(
      :box, move:, room:,
            length_cm: length, width_cm: width, height_cm: height, weight_kg: weight
    )
  end

  it "aggregates volume, weight, box count, and missing dimensions" do
    kitchen = create(:room, move:, name: "Kitchen")
    bedroom = create(:room, move:, name: "Bedroom")
    box(room: kitchen, dims: [40, 30, 25], weight: 8)   # vol 30_000
    box(room: kitchen)                                  # missing dims, no weight
    box(room: bedroom, dims: [50, 40, 20], weight: 6)   # vol 40_000
    box(room: nil, dims: [10, 10, 10])                  # unassigned, no weight

    result = described_class.new.call(move:, actor:).value!

    expect(result.total_volume_cm3).to eq(71_000)
    expect(result.total_weight_kg).to eq(14)
    expect(result.box_count).to eq(4)
    expect(result.missing_dimension_count).to eq(1)
  end

  it "groups per room (volume desc) with an unassigned bucket last" do
    kitchen = create(:room, move:, name: "Kitchen")
    bedroom = create(:room, move:, name: "Bedroom")
    box(room: kitchen, dims: [40, 30, 25], weight: 8)
    box(room: kitchen)
    box(room: bedroom, dims: [50, 40, 20], weight: 6)
    box(room: nil, dims: [10, 10, 10])

    rooms = described_class.new.call(move:, actor:).value!.rooms

    expect(rooms.map { |r| r.room&.name }).to eq(["Bedroom", "Kitchen", nil])
    kitchen_summary = rooms.find { |r| r.room == kitchen }
    expect(kitchen_summary.box_count).to eq(2)
    expect(kitchen_summary.volume_cm3).to eq(30_000)
    expect(kitchen_summary.missing_dimension_count).to eq(1)
  end

  it "reports nil totals when nothing has been measured" do
    box(room: nil) # no dimensions, no weight

    result = described_class.new.call(move:, actor:).value!

    expect(result.total_volume_cm3).to be_nil
    expect(result.total_weight_kg).to be_nil
    expect(result.box_count).to eq(1)
    expect(result.missing_dimension_count).to eq(1)
  end

  it "reads an archived (read-only) move" do
    archived = create(:move, :archived)
    create(:box, move: archived, length_cm: 40, width_cm: 30, height_cm: 25)

    result = described_class.new.call(move: archived)

    expect(result).to be_success
    expect(result.value!.total_volume_cm3).to eq(30_000)
  end

  it "emits a move.summary_viewed event" do
    allow(Rails.event).to receive(:notify)

    described_class.new.call(move:, actor:)

    expect(Rails.event).to have_received(:notify).with(
      "move.summary_viewed", hash_including(move_id: move.id, actor_id: actor.id)
    )
  end
end
