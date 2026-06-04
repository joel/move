# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organization do
  it "has a valid factory" do
    expect(build(:organization)).to be_valid
  end

  it "requires a name" do
    expect(build(:organization, name: "")).not_to be_valid
  end

  it "normalizes the slug to lowercase" do
    expect(create(:organization, slug: "ACME").slug).to eq("acme")
  end

  it "rejects invalid slug formats" do
    ["a", "-bad", "bad-", "has_underscore", "has.dot", "Spaces Here"].each do |slug|
      expect(build(:organization, slug:)).not_to be_valid, "expected #{slug.inspect} to be invalid"
    end
  end

  it "rejects reserved platform slugs" do
    expect(build(:organization, slug: "move")).not_to be_valid
  end

  it "enforces globally unique slugs (case-insensitive)" do
    create(:organization, slug: "acme")
    expect(build(:organization, slug: "ACME")).not_to be_valid
  end

  it "links members through organization_memberships" do
    organization = create(:organization)
    user = create(:user)
    create(:organization_membership, organization:, user:)
    expect(organization.users).to include(user)
  end
end
