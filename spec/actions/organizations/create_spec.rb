require "rails_helper"

RSpec.describe Organizations::Create do
  let(:owner) { create(:user) }

  before { allow(Apartment::Tenant).to receive(:create) }

  it "creates the org, an owner membership, provisions the tenant, returns Success" do
    result = described_class.new.call(name: "Acme", slug: "acme", owner: owner)

    expect(result).to be_success
    org = result.value!
    expect(org.slug).to eq("acme")
    expect(org.organization_memberships.find_by(user: owner)&.role).to eq("owner")
    expect(Apartment::Tenant).to have_received(:create).with("acme")
  end

  it "normalizes the slug before use" do
    result = described_class.new.call(name: "Acme", slug: "  ACME  ", owner: owner)
    expect(result.value!.slug).to eq("acme")
  end

  it "rejects reserved slugs without persisting or provisioning" do
    result = described_class.new.call(name: "Mail", slug: "mail", owner: owner)

    expect(result).to be_failure
    expect(result.failure).to eq(:reserved_slug)
    expect(Organization.count).to eq(0)
    expect(Apartment::Tenant).not_to have_received(:create)
  end

  it "returns validation errors for a malformed slug" do
    result = described_class.new.call(name: "Bad", slug: "Bad Slug", owner: owner)

    expect(result).to be_failure
    expect(result.failure).to be_a(ActiveModel::Errors)
    expect(Organization.count).to eq(0)
  end

  it "rolls back the registry row when tenant provisioning fails" do
    allow(Apartment::Tenant).to receive(:create).and_raise(StandardError, "boom")

    result = described_class.new.call(name: "Acme", slug: "acme", owner: owner)

    expect(result).to be_failure
    expect(Organization.count).to eq(0)
  end

  it "emits an organization.created event" do
    allow(Rails.event).to receive(:notify)
    described_class.new.call(name: "Acme", slug: "acme", owner: owner)

    expect(Rails.event).to have_received(:notify)
      .with("organization.created", hash_including(slug: "acme"))
  end
end
