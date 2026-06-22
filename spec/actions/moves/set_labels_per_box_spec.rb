# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::SetLabelsPerBox do
  let(:move) { create(:move) }
  let(:actor) { move.created_by }

  it "updates labels_per_box and emits an event" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, labels_per_box: "5", actor:)

    expect(result).to be_success
    expect(move.reload.labels_per_box).to eq(5)
    expect(Rails.event).to have_received(:notify).with(
      "move.labels_per_box_changed",
      hash_including(move_id: move.id, actor_id: actor.id, labels_per_box: 5)
    )
  end

  it "accepts the boundary values 1 and 10" do
    expect(described_class.new.call(move:, labels_per_box: "1", actor:)).to be_success
    expect(described_class.new.call(move:, labels_per_box: "10", actor:)).to be_success
  end

  it "rejects an out-of-range value without changing the move" do
    %w[0 11].each do |bad|
      result = described_class.new.call(move:, labels_per_box: bad, actor:)
      expect(result).to be_failure
      expect(result.failure).to eq(:invalid_labels_per_box)
    end
    expect(move.reload.labels_per_box).to eq(2) # default, unchanged
  end

  it "rejects a non-integer value (no event, no write)" do
    allow(Rails.event).to receive(:notify)

    %w[2.5 abc].each do |bad|
      result = described_class.new.call(move:, labels_per_box: bad, actor:)
      expect(result).to be_failure
      expect(result.failure).to eq(:invalid_labels_per_box)
    end
    expect(move.reload.labels_per_box).to eq(2)
    expect(Rails.event).not_to have_received(:notify)
  end

  it "fails :move_archived on an archived move" do
    archived = create(:move, :archived)

    result = described_class.new.call(move: archived, labels_per_box: "3", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
  end
end
