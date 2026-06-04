# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Onboarding" do
  let(:user) { create(:user) }

  it "requires authentication" do
    get "/onboarding/new"
    expect(response).to have_http_status(:unauthorized)
  end

  context "when authenticated" do
    before do
      stub_current_user(user)
      host! "move.workeverywhere.docker"
    end

    it "renders the create-organization form" do
      get "/onboarding/new"
      expect(response).to be_successful
    end

    it "creates the organization and makes the creator account admin" do
      expect do
        post "/onboarding", params: { organization: { name: "Acme Relocation", slug: "acme" } }
      end.to change(Organization, :count).by(1).and change(OrganizationMembership, :count).by(1)

      organization = Organization.find_by(slug: "acme")
      expect(organization.created_by_user).to eq(user)
      membership = organization.organization_memberships.find_by(user:)
      expect(membership.account_admin).to be(true)
      expect(response.location).to match(%r{//acme\.move\.workeverywhere\.docker/\z})
    end

    it "re-renders with errors on invalid input" do
      post "/onboarding", params: { organization: { name: "", slug: "Bad Slug!" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(Organization.count).to eq(0)
    end
  end
end
