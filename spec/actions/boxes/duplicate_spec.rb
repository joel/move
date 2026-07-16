# frozen_string_literal: true

require "rails_helper"

RSpec.describe Boxes::Duplicate do
  let(:creator) { create(:user) }
  let(:move) { create(:move, created_by: creator) }

  it "creates a new box copying only the source's dimensions" do
    source = create(:box, move:, number: "1",
                          length_cm: 40, width_cm: 30, height_cm: 25, weight_kg: 12,
                          description: "Pots and pans", fragile: true,
                          room: create(:room, move:, name: "Kitchen"))

    result = described_class.new.call(box: source, creator:)

    expect(result).to be_success
    box = result.value!
    aggregate_failures do
      expect(box.number).to eq("2")
      expect([box.length_cm, box.width_cm, box.height_cm]).to eq([40, 30, 25])
      # A duplicate is a new empty box of the same size — nothing else carries over.
      expect(box.weight_kg).to be_nil
      expect(box.description).to be_nil
      expect(box.room).to be_nil
      expect(box.fragile).to be(false)
      expect(box.status).to eq("packing")
      expect(box.qr_token).to be_present
      expect(box.qr_token).not_to eq(source.qr_token)
    end
  end

  # The card hides the control on a dimensionless box, but the action itself
  # stays total — a direct call still yields a plain new box.
  it "duplicates a dimensionless box as a plain new box" do
    source = create(:box, move:, number: "1")

    box = described_class.new.call(box: source, creator:).value!

    expect(box).to be_missing_dimensions
  end

  it "refuses to duplicate into an archived move" do
    archived = create(:move, :archived, created_by: creator)
    source = create(:box, move: archived, number: "1")

    result = described_class.new.call(box: source, creator:)

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
    expect(archived.boxes.count).to eq(1)
  end

  it "emits box.created for the duplicate" do
    source = create(:box, move:, number: "1")
    allow(Rails.event).to receive(:notify)

    box = described_class.new.call(box: source, creator:).value!

    expect(Rails.event).to have_received(:notify).with(
      "box.created", hash_including(box_id: box.id, move_id: move.id)
    )
  end
end
