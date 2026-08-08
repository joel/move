# frozen_string_literal: true

require "rails_helper"

RSpec.describe Boxes::CompleteIfEmpty do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  it "completes an emptied unpacking box with exactly one box.status_changed" do
    box = create(:box, :with_room, move:, status: "unpacking")
    create(:item, move:, box:, presence_state: "removed")

    allow(Rails.event).to receive(:notify)
    result = described_class.new.call(box:, actor:)

    aggregate_failures do
      expect(result.value!).to eq(box)
      expect(box.reload.status).to eq("unpacked")
      expect(Rails.event).to have_received(:notify)
        .with("box.status_changed", hash_including(to: "unpacked")).once
    end
  end

  it "reports not-applicable while items remain in the box" do
    box = create(:box, :with_room, move:, status: "unpacking")
    create(:item, move:, box:, presence_state: "in_box")

    allow(Rails.event).to receive(:notify)
    result = described_class.new.call(box:, actor:)

    aggregate_failures do
      expect(result.value!).to be_nil
      expect(box.reload.status).to eq("unpacking")
      expect(Rails.event).not_to have_received(:notify)
    end
  end

  it "no-ops on every non-unpacking phase, including already-unpacked" do
    %w[packing sealed in_transit unpacked].each do |status|
      box = create(:box, :with_room, move:, status: status)

      result = described_class.new.call(box:, actor:)

      expect(result.value!).to be_nil
      expect(box.reload.status).to eq(status)
    end
  end

  it "is not blocked by a discarded straggler (kept default scope)" do
    box = create(:box, :with_room, move:, status: "unpacking")
    create(:item, move:, box:, presence_state: "removed")
    create(:item, move:, box:, presence_state: "in_box").discard!

    expect(described_class.new.call(box:, actor:).value!).to eq(box)
    expect(box.reload.status).to eq("unpacked")
  end

  it "passes a TransitionStatus failure through (archived move)" do
    archived = create(:move, :archived, created_by: actor)
    box = create(:box, :with_room, move: archived, status: "unpacking")

    result = described_class.new.call(box:, actor:)

    expect(result).to eq(Dry::Monads::Failure(:move_archived))
    expect(box.reload.status).to eq("unpacking")
  end
end
