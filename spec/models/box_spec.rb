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
      expect(build(:box, status: "unpacking")).to be_unpacking.and(have_attributes(unpacked?: false))
      expect(build(:box, status: "unpacked")).to be_unpacked.and(have_attributes(unpacking?: false))
    end

    it "exposes the valid transitions for the current status" do
      expect(build(:box, status: "packing").available_transitions).to eq(%w[sealed])
      # sealed → unpacking (#738): a sealed box can open at the destination
      # without recording transit; also powers the find-list auto-open.
      expect(build(:box, status: "sealed").available_transitions).to eq(%w[packing in_transit unpacking])
      expect(build(:box, status: "sealed")).to be_can_transition_to("unpacking")
      # An unpacked box can be re-opened back to unpacking (D10 "Undo" / reopen).
      expect(build(:box, status: "unpacked").available_transitions).to eq(%w[unpacking])
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

  describe ".dimension_presets" do
    let(:move) { create(:move) }

    it "groups identical L×W×H and counts them, most-used first" do
      create_list(:box, 3, move:, length_cm: 40, width_cm: 30, height_cm: 25)
      create_list(:box, 2, move:, length_cm: 60, width_cm: 40, height_cm: 40)

      presets = move.boxes.dimension_presets

      expect(presets.first).to include(length_cm: 40, width_cm: 30, height_cm: 25, count: 3)
      expect(presets.pluck(:count)).to eq([3, 2])
    end

    it "offers a size used by only one box (reuse kicks in on box #2)" do
      create(:box, move:, length_cm: 40, width_cm: 30, height_cm: 25)

      presets = move.boxes.dimension_presets
      expect(presets.map { |p| p[:length_cm].to_i }).to eq([40])
      expect(presets.first[:count]).to eq(1)
    end

    it "honours a custom min_count to require repeats" do
      create(:box, move:, length_cm: 40, width_cm: 30, height_cm: 25)
      create_list(:box, 2, move:, length_cm: 60, width_cm: 40, height_cm: 40)

      sizes = move.boxes.dimension_presets(min_count: 2).map { |p| p[:length_cm].to_i }
      expect(sizes).to eq([60]) # the singleton 40×30×25 is filtered out
    end

    it "excludes boxes missing any linear dimension" do
      create_list(:box, 2, move:, length_cm: 40, width_cm: 30, height_cm: nil)
      create(:box, move:) # all nil

      expect(move.boxes.dimension_presets).to be_empty
    end

    it "tie-breaks by recency when counts are equal" do
      older = create_list(:box, 2, move:, length_cm: 10, width_cm: 10, height_cm: 10,
                                   created_at: 2.days.ago)
      create_list(:box, 2, move:, length_cm: 20, width_cm: 20, height_cm: 20,
                           created_at: 1.hour.ago)

      first = move.boxes.dimension_presets.first
      expect(first[:length_cm]).to eq(20)
      expect(first[:length_cm]).not_to eq(older.first.length_cm)
    end

    it "respects the limit" do
      4.times { |i| create_list(:box, 2, move:, length_cm: i + 1, width_cm: 1, height_cm: 1) }

      expect(move.boxes.dimension_presets(limit: 2).size).to eq(2)
    end
  end
end
