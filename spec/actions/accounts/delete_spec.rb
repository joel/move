require "rails_helper"

RSpec.describe Accounts::Delete do
  subject(:result) { described_class.new.call(user: user) }

  let(:user) { create(:user) }

  # The tenant schemas aren't really provisioned in specs, so `drop` is a spy,
  # `switch` (used to purge tenant attachments) just yields onto the public
  # connection, and `schema_exists?` reports the tenant as present so the drop
  # path runs.
  before do
    allow(Apartment::Tenant).to receive(:drop)
    allow(Apartment::Tenant).to receive(:switch).and_yield
    allow(ActiveRecord::Base.connection).to receive(:schema_exists?).and_call_original
    allow(ActiveRecord::Base.connection).to receive(:schema_exists?).with("acme").and_return(true)
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

    it "deletes the user's session handoff tokens (no FK to cascade them)" do
      SessionHandoffs::Mint.new.call(user: user, organization_slug: "acme").value!
      expect(SessionHandoffToken.where(user_id: user.id)).to exist

      result

      expect(SessionHandoffToken.where(user_id: user.id)).not_to exist
    end

    it "purges the tenant's Active Storage blobs as part of deletion" do
      # Attachment/blob tables live in public, so DROP SCHEMA would otherwise
      # orphan them. The blob (and its attachment) must be purged.
      media = create(:media)
      expect(media.image).to be_attached

      result

      expect(ActiveStorage::Attachment.exists?(record_type: "Media", record_id: media.id))
        .to be(false)
    end

    it "also purges blobs of soft-deleted (discarded) media" do
      # Media's default_scope { kept } hides discarded rows, so an unscoped sweep
      # is needed or their public blobs/files would survive the DROP SCHEMA.
      media = create(:media)
      media.discard
      expect(Media.kept).not_to include(media)

      result

      expect(ActiveStorage::Attachment.exists?(record_type: "Media", record_id: media.id))
        .to be(false)
    end

    it "still succeeds and drops the tenant when blob cleanup fails" do
      # Attachment capture/purge is best-effort: a failure must not turn the
      # deletion into a 500 once the tenant has been dropped.
      allow(Media).to receive(:unscoped).and_raise(RuntimeError, "storage down")

      expect(result).to be_success
      expect(User.exists?(user.id)).to be(false)
      expect(Apartment::Tenant).to have_received(:drop).with("acme")
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

  context "when the user is the sole owner but the org has other members" do
    let!(:organization) { create(:organization, slug: "acme") }

    before do
      create(:organization_membership, :owner, organization: organization, user: user)
      create(:organization_membership, organization: organization) # another member
    end

    it "refuses deletion rather than dropping a tenant others can see" do
      expect(result).to be_failure
      expect(result.failure).to eq(:owns_shared_data)
      expect(User.exists?(user.id)).to be(true)
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

  context "when the tenant drop fails" do
    let!(:organization) { create(:organization, slug: "acme") }

    before do
      create(:organization_membership, :owner, organization: organization, user: user)
      allow(Apartment::Tenant).to receive(:drop).and_raise(Apartment::ApartmentError, "locked")
    end

    it "aborts the deletion, leaving the account and org intact" do
      expect(result).to be_failure
      expect(result.failure).to eq(:tenant_drop_failed)
      expect(User.exists?(user.id)).to be(true)
      expect(Organization.exists?(organization.id)).to be(true)
    end

    it "does not strip the surviving tenant's media (purge only after a good drop)" do
      media = create(:media)

      expect(result).to be_failure
      expect(ActiveStorage::Attachment.exists?(record_type: "Media", record_id: media.id))
        .to be(true)
    end
  end

  context "when the user deletion fails after the orgs are torn down" do
    let!(:organization) { create(:organization, slug: "acme") }

    before do
      create(:organization_membership, :owner, organization: organization, user: user)
      allow(user).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)
    end

    it "returns Failure with the user still present (retryable)" do
      expect(result).to be_failure
      expect(User.exists?(user.id)).to be(true)
    end
  end
end
