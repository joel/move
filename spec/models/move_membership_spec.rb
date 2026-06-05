require "rails_helper"

RSpec.describe MoveMembership do
  describe "validations" do
    it "is valid with a known role" do
      expect(build(:move_membership, :admin)).to be_valid
    end

    it "rejects unknown roles" do
      expect(build(:move_membership, role: "captain")).not_to be_valid
    end

    it "forbids the same user joining one move twice" do
      move = create(:move)
      user = create(:user)
      create(:move_membership, move: move, user: user)

      expect(build(:move_membership, move: move, user: user)).not_to be_valid
    end
  end
end
