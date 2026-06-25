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

  describe ".primary_for (#346)" do
    let(:user) { create(:user) }

    it "returns the org of the OLDEST membership (deterministic)" do
      newer = create(:organization, slug: "newer-org")
      older = create(:organization, slug: "older-org")
      create(:organization_membership, organization: newer, user:, created_at: 1.day.ago)
      create(:organization_membership, organization: older, user:, created_at: 3.days.ago)

      expect(described_class.primary_for(user.id)).to eq(older)
    end

    it "breaks created_at ties by slug" do
      at = 2.days.ago
      b = create(:organization, slug: "b-org")
      a = create(:organization, slug: "a-org")
      create(:organization_membership, organization: b, user:, created_at: at)
      create(:organization_membership, organization: a, user:, created_at: at)

      expect(described_class.primary_for(user.id)).to eq(a)
    end

    it "returns nil when the user has no membership" do
      expect(described_class.primary_for(user.id)).to be_nil
    end
  end

  describe ".member? (#346)" do
    let(:user) { create(:user) }

    it "is true only for orgs the user belongs to" do
      mine = create(:organization, slug: "mine")
      create(:organization_membership, organization: mine, user:)
      create(:organization, slug: "theirs")

      expect(described_class.member?(user_id: user.id, slug: "mine")).to be(true)
      expect(described_class.member?(user_id: user.id, slug: "theirs")).to be(false)
      expect(described_class.member?(user_id: user.id, slug: "ghost")).to be(false)
    end
  end
end
