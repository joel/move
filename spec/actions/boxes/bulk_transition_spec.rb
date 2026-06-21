# frozen_string_literal: true

require "rails_helper"

RSpec.describe Boxes::BulkTransition do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  def bulk(to)
    described_class.new.call(move:, to:, actor:)
  end

  it "seals every packing box that has a room" do
    create_list(:box, 3, :with_room, move:, status: "packing")

    result = bulk("sealed")

    expect(result).to be_success
    expect(result.value!.transitioned).to eq(3)
    expect(result.value!.skipped).to be_empty
    expect(move.boxes.where(status: "sealed").count).to eq(3)
  end

  it "skips a roomless box on a seal and reports it, sealing the rest" do
    create(:box, :with_room, move:, status: "packing", number: "1")
    roomless = create(:box, move:, status: "packing", room: nil, number: "2")
    create(:box, :with_room, move:, status: "packing", number: "3")

    result = bulk("sealed").value!

    expect(result.transitioned).to eq(2)
    expect(result.skipped).to eq([{ number: roomless.number, reason: :room_required }])
    expect(roomless.reload.status).to eq("packing")
    expect(move.boxes.where(status: "sealed").count).to eq(2)
  end

  it "only touches boxes in the source state (a sealed box is untouched during a seal step)" do
    packing = create(:box, :with_room, move:, status: "packing")
    sealed = create(:box, :with_room, move:, status: "sealed")

    bulk("sealed")

    expect(packing.reload.status).to eq("sealed")
    expect(sealed.reload.status).to eq("sealed") # unchanged, not double-transitioned
  end

  it "cascades in-box items to removed when marking unpacking boxes unpacked" do
    box = create(:box, :with_room, move:, status: "unpacking")
    item = create(:item, box:, move:, presence_state: "in_box")

    result = bulk("unpacked")

    expect(result.value!.transitioned).to eq(1)
    expect(box.reload.status).to eq("unpacked")
    expect(item.reload.presence_state).to eq("removed")
  end

  it "reports skipped box numbers in numeric (print) order" do
    %w[10 2].each { |n| create(:box, move:, status: "packing", room: nil, number: n) }

    skipped = bulk("sealed").value!.skipped

    expect(skipped.pluck(:number)).to eq(%w[2 10])
  end

  it "emits a box.status_changed per transitioned box" do
    create_list(:box, 2, :with_room, move:, status: "packing")
    allow(Rails.event).to receive(:notify).and_call_original

    bulk("sealed")

    expect(Rails.event).to have_received(:notify)
      .with("box.status_changed", hash_including(to: "sealed")).twice
  end

  it "fails with :move_archived on an archived move" do
    archived = create(:move, :archived, created_by: actor)
    create(:box, :with_room, move: archived, status: "packing")

    result = described_class.new.call(move: archived, to: "sealed", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
  end

  it "fails with :invalid_step for a target outside the forward steps" do
    create(:box, :with_room, move:, status: "sealed")

    result = bulk("packing") # a backward edge — not a forward bulk step

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_step)
  end

  it "succeeds with zero transitions when no box is in the source state" do
    result = bulk("in_transit") # no sealed boxes exist

    expect(result).to be_success
    expect(result.value!.transitioned).to eq(0)
    expect(result.value!.skipped).to be_empty
  end
end
