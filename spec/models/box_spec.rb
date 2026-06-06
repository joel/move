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

  describe "#sealed?" do
    it "is false while packing and true once moved on" do
      expect(build(:box, status: "packing")).not_to be_sealed
      expect(build(:box, status: "sealed")).to be_sealed
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
