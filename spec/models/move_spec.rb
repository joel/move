require "rails_helper"

RSpec.describe Move do
  describe "validations" do
    it "is valid with a name, status, unit system and creator" do
      expect(build(:move)).to be_valid
    end

    it "requires a name" do
      expect(build(:move, name: nil)).not_to be_valid
    end

    it "rejects unknown statuses" do
      expect(build(:move, status: "lost")).not_to be_valid
    end

    it "rejects unknown unit systems" do
      expect(build(:move, unit_system: "furlongs")).not_to be_valid
    end
  end

  describe "#writable?" do
    it "is writable unless archived" do
      expect(build(:move, status: "planned")).to be_writable
      expect(build(:move, :archived)).not_to be_writable
    end
  end

  describe "#admin?" do
    it "is true only for an admin member" do
      move = create(:move)
      admin = create(:user)
      member = create(:user)
      create(:move_membership, :admin, move:, user: admin)
      create(:move_membership, move:, user: member)

      expect(move.admin?(admin)).to be(true)
      expect(move.admin?(member)).to be(false)
      expect(move.admin?(create(:user))).to be(false)
      expect(move.admin?(nil)).to be(false)
    end
  end
end
