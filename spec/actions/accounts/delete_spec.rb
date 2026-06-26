require "rails_helper"

RSpec.describe Accounts::Delete do
  subject(:result) { described_class.new.call(user: user) }

  let(:user) { create(:user) }

  # The tenant schemas aren't really provisioned in specs, so `drop` is a spy.
  before do
    allow(Apartment::Tenant).to receive(:drop)
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

  # Belonging to an org the user does not solely own is deliberately unsupported
  # until ownership transfer exists: deleting them would strand the moves they
  # created in the surviving tenant (Move#created_by is required, no FK).
  context "when the organization has another owner" do
    let!(:organization) { create(:organization, slug: "acme") }
    let!(:membership) do
      create(:organization_membership, :owner, organization: organization, user: user)
    end

    before { create(:organization_membership, :owner, organization: organization) }

    it "refuses deletion, keeping the account, org and schema intact" do
      expect(result).to be_failure
      expect(result.failure).to eq(:owns_shared_data)
      expect(User.exists?(user.id)).to be(true)
      expect(OrganizationMembership.exists?(membership.id)).to be(true)
      expect(Organization.exists?(organization.id)).to be(true)
      expect(Apartment::Tenant).not_to have_received(:drop)
    end
  end

  context "when the user is a non-owner member" do
    let!(:organization) { create(:organization, slug: "acme") }

    before do
      create(:organization_membership, organization: organization, user: user)
      create(:organization_membership, :owner, organization: organization)
    end

    it "refuses deletion rather than stranding the org" do
      expect(result).to be_failure
      expect(result.failure).to eq(:owns_shared_data)
      expect(User.exists?(user.id)).to be(true)
      expect(Organization.exists?(organization.id)).to be(true)
      expect(Apartment::Tenant).not_to have_received(:drop)
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
