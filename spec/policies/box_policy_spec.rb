# frozen_string_literal: true

require "rails_helper"

RSpec.describe BoxPolicy do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }

  describe "label? / manifest?" do
    it "permits any signed-in user (read access matches viewing the box)" do
      policy = described_class.new(box, user: user)

      expect(policy.apply(:label?)).to be(true)
      expect(policy.apply(:manifest?)).to be(true)
    end

    it "denies an anonymous user" do
      policy = described_class.new(box, user: nil)

      expect(policy.apply(:label?)).to be(false)
      expect(policy.apply(:manifest?)).to be(false)
    end
  end
end
