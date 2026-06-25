# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionHandoffs::TargetResolver do
  let(:user) { create(:user) }
  let(:acme) { create(:organization, slug: "acme") }
  let(:globex) { create(:organization, slug: "globex") }

  # user is a member of both acme and globex; acme is the primary fallback.
  before do
    create(:organization_membership, organization: acme, user:)
    create(:organization_membership, organization: globex, user:)
  end

  def resolve(current_tenant:, omniauth_org: nil, primary_slug: "acme")
    described_class.new(
      account_id: user.id, current_tenant:, omniauth_org:, primary_slug:
    ).call
  end

  it "prefers the originating subdomain tenant when the user is a member" do
    expect(resolve(current_tenant: "globex")).to eq("globex")
  end

  it "prefers the subdomain tenant over the Google-bridge org param" do
    expect(resolve(current_tenant: "globex", omniauth_org: "acme")).to eq("globex")
  end

  it "honours the Google-bridge org param on the apex when the user is a member" do
    expect(resolve(current_tenant: "public", omniauth_org: "globex")).to eq("globex")
  end

  it "treats the apex (public / blank tenant) as no origin → primary" do
    expect(resolve(current_tenant: "public")).to eq("acme")
    expect(resolve(current_tenant: nil)).to eq("acme")
  end

  it "rejects an origin the user is NOT a member of → primary" do
    expect(resolve(current_tenant: "stranger")).to eq("acme") # subdomain origin
    expect(resolve(current_tenant: "public", omniauth_org: "stranger")).to eq("acme") # bridge
  end

  it "rejects an origin slug that does not exist → primary" do
    expect(resolve(current_tenant: "public", omniauth_org: "ghost-org")).to eq("acme")
  end

  it "rejects a non-string (array/hash) omniauth org param → primary (#355)" do
    # Rack can deliver org[]=globex as an array; it must not pass the IN-clause
    # membership check and get returned verbatim as a malformed slug.
    expect(resolve(current_tenant: "public", omniauth_org: ["globex"])).to eq("acme")
    expect(resolve(current_tenant: "public", omniauth_org: { "x" => "globex" })).to eq("acme")
  end

  it "returns the primary slug when there is no usable origin" do
    expect(resolve(current_tenant: "public", omniauth_org: nil, primary_slug: "acme")).to eq("acme")
  end

  it "returns nil when the account has no org at all (caller lands on apex)" do
    expect(resolve(current_tenant: "public", primary_slug: nil)).to be_nil
  end
end
