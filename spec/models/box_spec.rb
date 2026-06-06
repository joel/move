# frozen_string_literal: true

require "rails_helper"

RSpec.describe Box do
  it "has a valid factory" do
    expect(build(:box)).to be_valid
  end

  describe "validations" do
    it "requires a number, qr_token and a known status" do
      box = build(:box, number: nil, qr_token: nil, status: "bogus")
      expect(box).not_to be_valid
      expect(box.errors[:number]).to be_present
      expect(box.errors[:qr_token]).to be_present
      expect(box.errors[:status]).to be_present
    end

    it "requires a numeric number" do
      expect(build(:box, number: "A1")).not_to be_valid
    end

    it "rejects a number beyond the bigint range (keeps the ordering cast safe)" do
      expect(build(:box, number: "9" * 25)).not_to be_valid
    end

    it "enforces number uniqueness within a Move" do
      move = create(:move)
      create(:box, move:, number: "1")
      expect(build(:box, move:, number: "1")).not_to be_valid
    end

    it "allows the same number in a different Move" do
      create(:box, move: create(:move), number: "1")
      expect(build(:box, move: create(:move), number: "1")).to be_valid
    end

    it "enforces qr_token uniqueness" do
      create(:box, qr_token: "shared-token")
      expect(build(:box, qr_token: "shared-token")).not_to be_valid
    end
  end

  describe "lifecycle predicates" do
    it "distinguishes packing, sealed and packed states precisely" do
      expect(build(:box, status: "packing")).to be_packing.and(be_capturable).and(have_attributes(packed?: false, sealed?: false))
      expect(build(:box, status: "sealed")).to be_sealed.and(be_packed).and(have_attributes(capturable?: false))
      expect(build(:box, status: "in_transit")).to be_packed.and(have_attributes(sealed?: false, capturable?: false))
    end

    it "exposes the valid transitions for the current status" do
      expect(build(:box, status: "packing").available_transitions).to eq(%w[sealed])
      expect(build(:box, status: "sealed").available_transitions).to eq(%w[packing in_transit])
      expect(build(:box, status: "unpacked").available_transitions).to be_empty
      expect(build(:box, status: "packing")).to be_can_transition_to("sealed")
      expect(build(:box, status: "packing")).not_to be_can_transition_to("in_transit")
    end
  end

  describe "#volume_cm3" do
    it "derives volume from dimensions, nil when incomplete" do
      expect(build(:box, :with_dimensions).volume_cm3).to eq(40 * 30 * 25)
      expect(build(:box, :with_dimensions, height_cm: nil).volume_cm3).to be_nil
    end
  end

  describe "#missing_dimensions?" do
    it "is true when any linear dimension is blank" do
      expect(build(:box)).to be_missing_dimensions
      expect(build(:box, :with_dimensions)).not_to be_missing_dimensions
      expect(build(:box, :with_dimensions, height_cm: nil)).to be_missing_dimensions
    end
  end

  describe ".ordered" do
    it "sorts by numeric box number, not lexicographically" do
      move = create(:move)
      %w[10 2 1].each { |n| create(:box, move:, number: n) }
      expect(move.boxes.ordered.pluck(:number)).to eq(%w[1 2 10])
    end
  end
end
