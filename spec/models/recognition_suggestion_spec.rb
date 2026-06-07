# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionSuggestion do
  it "has a valid factory" do
    expect(build(:recognition_suggestion)).to be_valid
  end

  describe ".unresolved" do
    it "returns only pending and conflict suggestions" do
      move = create(:move)
      pending = create(:recognition_suggestion, move:, state: "pending")
      conflict = create(:recognition_suggestion, :conflict, move:)
      create(:recognition_suggestion, move:, state: "accepted")

      expect(described_class.unresolved).to contain_exactly(pending, conflict)
    end
  end

  describe ".by_confidence" do
    it "orders lowest confidence first, NULLs last" do
      move = create(:move)
      hi = create(:recognition_suggestion, move:, confidence_score: 0.9)
      lo = create(:recognition_suggestion, move:, confidence_score: 0.2)
      none = create(:recognition_suggestion, move:, confidence_score: nil)

      expect(described_class.by_confidence.to_a).to eq([lo, hi, none])
    end
  end

  it "reports confidence as a percent (nil when unscored)" do
    expect(build(:recognition_suggestion, confidence_score: 0.32).confidence_percent).to eq(32)
    expect(build(:recognition_suggestion, confidence_score: nil).confidence_percent).to be_nil
  end
end
