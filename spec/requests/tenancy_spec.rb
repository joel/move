# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Subdomain tenancy" do
  let(:user) { create(:user) }
  let!(:organization) { create(:organization, slug: "acme") }

  it "serves the apex host with no organization context" do
    host! "move.workeverywhere.docker"
    get "/"
    expect(response).to be_successful
  end

  it "renders the tenant home for a member on the org subdomain" do
    create(:organization_membership, organization:, user:)
    stub_current_user(user)
    host! "acme.move.workeverywhere.docker"

    get "/"

    expect(response).to be_successful
    expect(response.body).to include(organization.name)
  end

  it "returns a non-disclosing 404 for an unknown subdomain" do
    host! "ghost.move.workeverywhere.docker"
    get "/"
    expect(response).to have_http_status(:not_found)
  end

  it "returns a non-disclosing 404 for an authenticated non-member" do
    stub_current_user(user) # not a member of `acme`
    host! "acme.move.workeverywhere.docker"

    get "/"

    expect(response).to have_http_status(:not_found)
  end

  it "redirects anonymous subdomain visitors to the apex login" do
    stub_current_user(nil)
    host! "acme.move.workeverywhere.docker"

    get "/"

    expect(response.location).to match(%r{//move\.workeverywhere\.docker/login\z})
  end
end
