# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::SetUnitSystem do
  let(:move) { create(:move, unit_system: "metric") }
  let(:actor) { move.created_by }

  it "updates the unit system and emits an event" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, unit_system: "imperial", actor:)

    expect(result).to be_success
    expect(move.reload.unit_system).to eq("imperial")
    expect(Rails.event).to have_received(:notify).with(
      "move.unit_system_changed",
      hash_including(move_id: move.id, actor_id: actor.id, unit_system: "imperial")
    )
  end

  it "rejects an unknown unit system without changing the move" do
    result = described_class.new.call(move:, unit_system: "furlongs")

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_unit_system)
    expect(move.reload.unit_system).to eq("metric")
  end

  it "does not emit an event for an invalid unit system" do
    allow(Rails.event).to receive(:notify)

    described_class.new.call(move:, unit_system: "furlongs")

    expect(Rails.event).not_to have_received(:notify)
  end
end
