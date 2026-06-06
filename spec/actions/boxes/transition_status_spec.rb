require "rails_helper"

RSpec.describe Boxes::TransitionStatus do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  def transition(box, to)
    described_class.new.call(box:, to:, actor:)
  end

  it "seals a packing box that has a room" do
    box = create(:box, :with_room, move:, status: "packing")

    expect(transition(box, "sealed")).to be_success
    expect(box.reload.status).to eq("sealed")
  end

  it "refuses to seal a box without a room" do
    box = create(:box, move:, status: "packing", room: nil)

    result = transition(box, "sealed")

    expect(result).to be_failure
    expect(result.failure).to eq(:room_required)
    expect(box.reload.status).to eq("packing")
  end

  it "unseals a sealed box" do
    box = create(:box, :with_room, move:, status: "sealed")

    expect(transition(box, "packing")).to be_success
    expect(box.reload.status).to eq("packing")
  end

  it "rejects an illegal jump (packing -> unpacked)" do
    box = create(:box, :with_room, move:, status: "packing")

    result = transition(box, "unpacked")

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_transition)
    expect(box.reload.status).to eq("packing")
  end

  it "walks the forward lifecycle" do
    box = create(:box, :with_room, move:, status: "sealed")
    %w[in_transit unpacking unpacked].each do |to|
      expect(transition(box, to)).to be_success
      expect(box.reload.status).to eq(to)
    end
  end

  it "emits a box.status_changed event" do
    box = create(:box, :with_room, move:, status: "packing")
    allow(Rails.event).to receive(:notify)

    transition(box, "sealed")

    expect(Rails.event).to have_received(:notify).with(
      "box.status_changed", hash_including(to: "sealed")
    )
  end
end
