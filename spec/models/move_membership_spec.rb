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

  describe "role predicates" do
    it "reports its role" do
      expect(build(:move_membership, role: "admin")).to be_admin
      expect(build(:move_membership, role: "contributor")).to be_contributor
      expect(build(:move_membership, role: "viewer")).to be_viewer
    end

    describe "#can_edit?" do
      it "is true for admins and contributors" do
        expect(build(:move_membership, role: "admin").can_edit?).to be(true)
        expect(build(:move_membership, role: "contributor").can_edit?).to be(true)
      end

      it "is false for viewers" do
        expect(build(:move_membership, role: "viewer").can_edit?).to be(false)
      end
    end
  end
end
