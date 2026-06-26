require "rails_helper"

RSpec.describe Accounts::Delete do
  subject(:result) { described_class.new.call(user: user) }

  let(:user) { create(:user) }

  # Apartment schema operations are stubbed: the tenant schemas aren't really
  # provisioned in specs, so `drop` is a spy and `switch` just yields onto the
  # public connection (where the template tables live).
  before do
    allow(Apartment::Tenant).to receive(:drop)
    allow(Apartment::Tenant).to receive(:switch).and_yield
    allow(Rails.event).to receive(:notify)
  end

  context "when the user is the sole owner of an organization" do
    let!(:organization) { create(:organization, slug: "acme") }
    let!(:membership) do
      create(:organization_membership, :owner, organization: organization, user: user)
    end

    it "deletes the user and returns Success" do
      expect(result).to be_success
      expect(result.value!).to eq(user.id)
      expect(User.exists?(user.id)).to be(false)
    end

    it "destroys the org registry row and drops its tenant schema" do
      result
      expect(Organization.exists?(organization.id)).to be(false)
      expect(OrganizationMembership.exists?(membership.id)).to be(false)
      expect(Apartment::Tenant).to have_received(:drop).with("acme")
    end

    it "emits account.deleted with the dropped organization slug" do
      result
      expect(Rails.event).to have_received(:notify).with(
        "account.deleted",
        hash_including(user_id: user.id, organizations_dropped: ["acme"])
      )
    end
  end

  context "when the organization has another owner" do
    let!(:organization) { create(:organization, slug: "acme") }
    let!(:co_owner) { create(:organization_membership, :owner, organization: organization) }
    let!(:membership) do
      create(:organization_membership, :owner, organization: organization, user: user)
    end

    it "removes the user's membership but keeps the org and its schema" do
      expect(result).to be_success
      expect(User.exists?(user.id)).to be(false)
      expect(OrganizationMembership.exists?(membership.id)).to be(false)
      expect(Organization.exists?(organization.id)).to be(true)
      expect(OrganizationMembership.exists?(co_owner.id)).to be(true)
      expect(Apartment::Tenant).not_to have_received(:drop)
    end
  end

  context "when the user is a non-owner member" do
    let!(:organization) { create(:organization, slug: "acme") }
    let!(:membership) { create(:organization_membership, organization: organization, user: user) }

    before { create(:organization_membership, :owner, organization: organization) }

    it "removes only the user's membership and keeps the org" do
      expect(result).to be_success
      expect(OrganizationMembership.exists?(membership.id)).to be(false)
      expect(Organization.exists?(organization.id)).to be(true)
      expect(Apartment::Tenant).not_to have_received(:drop)
    end

    it "cleans the user's tenant-local move memberships in the kept org" do
      move = create(:move)
      move_membership = create(:move_membership, move: move, user: user)

      result

      expect(Apartment::Tenant).to have_received(:switch).with("acme")
      expect(MoveMembership.exists?(move_membership.id)).to be(false)
    end
  end

  context "with no organizations" do
    it "deletes the user without dropping anything" do
      expect(result).to be_success
      expect(User.exists?(user.id)).to be(false)
      expect(Apartment::Tenant).not_to have_received(:drop)
    end
  end

  context "when the relational deletion fails" do
    let!(:organization) { create(:organization, slug: "acme") }

    before do
      create(:organization_membership, :owner, organization: organization, user: user)
      allow(user).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)
    end

    it "returns Failure and leaves the account and org intact, dropping nothing" do
      expect(result).to be_failure
      expect(User.exists?(user.id)).to be(true)
      expect(Organization.exists?(organization.id)).to be(true)
      expect(Apartment::Tenant).not_to have_received(:drop)
    end
  end
end
