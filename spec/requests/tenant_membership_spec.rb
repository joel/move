# frozen_string_literal: true

require "rails_helper"

# The tenant boundary authorizes ORGANIZATION MEMBERSHIP, not merely a session.
# A session that reaches an org subdomain the user does not belong to gets a
# non-disclosing 404 on every tenant surface — including POST /moves, which would
# otherwise let them create a Move and self-assign admin inside a foreign tenant.
# (Reads were already relation-scoped; this closes the create/foothold gap.)
# See TenantController#require_membership! and ApplicationController#member_of_current_tenant?.
RSpec.describe "Tenant membership boundary" do
  let(:user) { create(:user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
    allow(Apartment::Tenant).to receive(:current).and_return("acme")
    # Exercise the REAL membership check (stub_current_user defaults it to true so
    # the rest of the suite isn't 404'd; here we want the actual boundary).
    allow_any_instance_of(ApplicationController) # rubocop:disable RSpec/AnyInstance
      .to receive(:member_of_current_tenant?).and_call_original
  end

  context "when the user is a member of the current Organization" do
    before do
      create(:organization, slug: "acme").organization_memberships.create!(user:, role: "member")
    end

    it "allows a tenant surface" do
      get moves_path
      expect(response).to have_http_status(:ok)
    end

    it "allows creating a Move" do
      expect { post moves_path, params: { move: { name: "Beach House", unit_system: "metric" } } }
        .to change(Move, :count).by(1)
      expect(response).to redirect_to(moves_path)
    end
  end

  context "when the user is NOT a member of the current Organization" do
    before { create(:organization, slug: "acme") } # org exists; user is not a member

    it "404s a tenant surface (non-disclosing)" do
      get moves_path
      expect(response).to have_http_status(:not_found)
    end

    it "404s POST /moves and creates nothing (no cross-tenant Move + self-admin)" do
      expect { post moves_path, params: { move: { name: "Intruder", unit_system: "metric" } } }
        .not_to change(Move, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "404s a non-member who hasn't accepted terms (no 302 to the terms wall)" do
      # The terms gate must not redirect a non-member (that would disclose the
      # subdomain resolves to a real tenant); the membership 404 wins uniformly.
      stub_current_user(create(:user), accept_terms: false)
      allow_any_instance_of(ApplicationController) # rubocop:disable RSpec/AnyInstance
        .to receive(:member_of_current_tenant?).and_call_original

      get moves_path

      expect(response).to have_http_status(:not_found)
    end
  end
end
