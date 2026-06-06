# frozen_string_literal: true

require "rails_helper"

RSpec.describe BoxMeasurements do
  let(:box) { build(:box, length_cm: 40, width_cm: 30, height_cm: 25, weight_kg: 8) }

  describe "metric" do
    subject(:m) { described_class.new(box, unit_system: "metric") }

    it { expect(m.dimensions).to eq("40 × 30 × 25 cm") }
    it { expect(m.volume).to eq("0.030 m³") }
    it { expect(m.weight).to eq("8.0 kg") }
  end

  describe "imperial" do
    subject(:m) { described_class.new(box, unit_system: "imperial") }

    it { expect(m.dimensions).to eq("15.7 × 11.8 × 9.8 in") }
    it { expect(m.volume).to eq("1.06 ft³") }
    it { expect(m.weight).to eq("17.6 lb") }
  end

  describe "missing data" do
    it "returns nil for absent dimensions and weight" do
      bare = build(:box, length_cm: nil, weight_kg: nil)
      m = described_class.new(bare, unit_system: "metric")
      expect(m.dimensions).to be_nil
      expect(m.volume).to be_nil
      expect(m.weight).to be_nil
    end
  end
end
