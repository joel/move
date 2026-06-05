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
end
