# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveMeasurements do
  describe "metric" do
    subject(:m) { described_class.new(unit_system: "metric") }

    it "formats volume in m³, stripping trailing zeros" do
      expect(m.volume(30_000)).to have_attributes(value: "0.03", unit: "m³")
      expect(m.volume(42_500_000)).to have_attributes(value: "42.5", unit: "m³")
      expect(m.volume(12_000_000)).to have_attributes(value: "12", unit: "m³")
    end

    it "formats weight in kg with a thousands separator" do
      expect(m.weight(8)).to have_attributes(value: "8", unit: "kg")
      expect(m.weight(1240)).to have_attributes(value: "1,240", unit: "kg")
    end
  end

  describe "imperial" do
    subject(:m) { described_class.new(unit_system: "imperial") }

    it "converts volume to ft³" do
      expect(m.volume(30_000)).to have_attributes(value: "1.06", unit: "ft³")
    end

    it "converts weight to lb" do
      expect(m.weight(8)).to have_attributes(value: "18", unit: "lb")
    end
  end

  describe "absent values" do
    subject(:m) { described_class.new(unit_system: "metric") }

    it "returns nil for nil volume and weight" do
      expect(m.volume(nil)).to be_nil
      expect(m.weight(nil)).to be_nil
    end
  end
end
