# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::Move do
  let(:mover) { create(:user) }
  let(:move) { create(:move, created_by: mover) }
  let(:source) { create(:box, move:) }
  let(:target) { create(:box, move:) }
  let(:item) { create(:item, :manual, move:, box: source) }

  it "moves the item to the target box and keeps presence in_box" do
    result = described_class.new.call(item:, target_box: target, mover:)

    expect(result).to be_success
    expect(item.reload.box).to eq(target)
    expect(item.presence_state).to eq("in_box")
  end

  it "rejects a move to the same box" do
    result = described_class.new.call(item:, target_box: source, mover:)
    expect(result.failure).to eq(:same_box)
  end

  it "rejects a move across Moves" do
    other = create(:box, move: create(:move))
    result = described_class.new.call(item:, target_box: other, mover:)
    expect(result.failure).to eq(:cross_move)
  end

  it "rejects a nil target box" do
    expect(described_class.new.call(item:, target_box: nil, mover:).failure).to eq(:box_missing)
  end

  it "refuses to move a removed item (restore first)" do
    item.update!(presence_state: "removed")

    result = described_class.new.call(item:, target_box: target, mover:)

    expect(result.failure).to eq(:removed)
    expect(item.reload.box).to eq(source)
    expect(item.presence_state).to eq("removed")
  end
end
