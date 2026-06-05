require "rails_helper"

RSpec.describe OrganizationMembership do
  describe "validations" do
    it "is valid with a known role" do
      expect(build(:organization_membership, role: "owner")).to be_valid
    end

    it "rejects unknown roles" do
      expect(build(:organization_membership, role: "wizard")).not_to be_valid
    end

    it "forbids the same user joining one organization twice" do
      org = create(:organization)
      user = create(:user)
      create(:organization_membership, organization: org, user: user)

      expect(build(:organization_membership, organization: org, user: user)).not_to be_valid
    end

    it "allows the same user in different organizations" do
      user = create(:user)
      create(:organization_membership, organization: create(:organization), user: user)

      expect(build(:organization_membership, organization: create(:organization), user: user)).to be_valid
    end
  end
end
