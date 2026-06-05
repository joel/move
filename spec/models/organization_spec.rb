require "rails_helper"

RSpec.describe Organization do
  describe "validations" do
    it "is valid with a name and a well-formed slug" do
      expect(build(:organization, name: "Acme", slug: "acme")).to be_valid
    end

    it "requires a name" do
      expect(build(:organization, name: nil)).not_to be_valid
    end

    it "requires a slug" do
      expect(build(:organization, slug: nil)).not_to be_valid
    end

    it "rejects slugs that are not DNS-label safe" do
      %w[Acme -acme acme- a 1acme acme_co].each do |bad|
        expect(build(:organization, slug: bad)).not_to be_valid, "expected #{bad.inspect} to be invalid"
      end
    end

    it "accepts hyphenated lowercase slugs" do
      expect(build(:organization, slug: "acme-movers-2")).to be_valid
    end

    it "enforces case-insensitive slug uniqueness" do
      create(:organization, slug: "acme")
      expect(build(:organization, slug: "ACME")).not_to be_valid
    end
  end

  describe "associations" do
    it "has many memberships and users through them" do
      org = create(:organization)
      user = create(:user)
      create(:organization_membership, organization: org, user: user)

      expect(org.users).to include(user)
    end
  end
end
