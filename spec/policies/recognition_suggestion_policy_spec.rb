# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionSuggestionPolicy do
  let(:user) { create(:user) }

  describe "read access" do
    it "permits any signed-in user to view the queue/item" do
      suggestion = create(:recognition_suggestion)
      expect(described_class.new(suggestion, user:).apply(:show?)).to be(true)
    end

    it "denies an anonymous user" do
      suggestion = create(:recognition_suggestion)
      expect(described_class.new(suggestion, user: nil).apply(:show?)).to be(false)
    end
  end

  describe "resolution (keep/correct/mark_false_positive)" do
    it "permits a signed-in user on a writable Move" do
      suggestion = create(:recognition_suggestion, move: create(:move, status: "started"))
      policy = described_class.new(suggestion, user:)

      %i[keep? correct? mark_false_positive?].each do |rule|
        expect(policy.apply(rule)).to be(true), "expected #{rule} permitted"
      end
    end

    it "denies resolution on an archived Move" do
      suggestion = create(:recognition_suggestion, move: create(:move, status: "archived"))
      policy = described_class.new(suggestion, user:)

      %i[keep? correct? mark_false_positive?].each do |rule|
        expect(policy.apply(rule)).to be(false), "expected #{rule} denied"
      end
    end
  end
end
