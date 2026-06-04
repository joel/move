# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrganizationMembership do
  it "has a valid factory" do
    expect(build(:organization_membership)).to be_valid
  end

  it "is unique per (organization, user)" do
    existing = create(:organization_membership)
    duplicate = build(:organization_membership,
                      organization: existing.organization, user: existing.user)
    expect(duplicate).not_to be_valid
  end

  it "allows the same user in different organizations" do
    user = create(:user)
    create(:organization_membership, user:)
    expect(build(:organization_membership, user:)).to be_valid
  end
end
