# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::SetAutoConfirmThreshold do
  let(:move) { create(:move) }
  let(:actor) { move.created_by }

  it "updates the threshold and emits an event" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, threshold: "0.6", actor:)

    expect(result).to be_success
    expect(move.reload.auto_confirm_threshold).to eq(0.6)
    expect(Rails.event).to have_received(:notify).with(
      "move.auto_confirm_threshold_changed",
      hash_including(move_id: move.id, actor_id: actor.id, auto_confirm_threshold: 0.6)
    )
  end

  it "accepts the boundary values 0 and 1" do
    expect(described_class.new.call(move:, threshold: "0", actor:)).to be_success
    expect(described_class.new.call(move:, threshold: "1", actor:)).to be_success
  end

  it "rejects an out-of-range threshold without changing the move" do
    result = described_class.new.call(move:, threshold: "1.5", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_threshold)
    expect(move.reload.auto_confirm_threshold).to eq(0.8)
  end

  it "rejects a non-numeric threshold" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, threshold: "high", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_threshold)
    expect(Rails.event).not_to have_received(:notify)
  end
end
