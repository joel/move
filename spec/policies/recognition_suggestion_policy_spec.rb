# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionSuggestionPolicy do
  let(:user) { create(:user) }

  describe "read access" do
    it "permits a member (any role) to view the queue/item" do
      move = create(:move)
      create(:move_membership, move:, user:, role: "viewer")

      expect(described_class.new(create(:recognition_suggestion, move:), user:).apply(:show?)).to be(true)
    end

    it "denies a signed-in non-member" do
      expect(described_class.new(create(:recognition_suggestion), user:).apply(:show?)).to be(false)
    end

    it "denies an anonymous user" do
      expect(described_class.new(create(:recognition_suggestion), user: nil).apply(:show?)).to be(false)
    end
  end

  describe "resolution (keep/correct/mark_false_positive)" do
    it "permits an editor (admin/contributor) on a writable Move" do
      move = create(:move, status: "started")
      create(:move_membership, move:, user:, role: "contributor")
      policy = described_class.new(create(:recognition_suggestion, move:), user:)

      %i[keep? correct? mark_false_positive?].each do |rule|
        expect(policy.apply(rule)).to be(true), "expected #{rule} permitted"
      end
    end

    it "denies a viewer" do
      move = create(:move, status: "started")
      create(:move_membership, move:, user:, role: "viewer")

      expect(described_class.new(create(:recognition_suggestion, move:), user:).apply(:keep?)).to be(false)
    end

    it "denies resolution on an archived Move" do
      move = create(:move, :archived)
      create(:move_membership, move:, user:, role: "admin")

      expect(described_class.new(create(:recognition_suggestion, move:), user:).apply(:keep?)).to be(false)
    end
  end
end
