# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Members" do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin) } # creator → admin member
  let(:organization) { Organization.create!(name: "Acme", slug: "acme") }
  let(:candidate) { create(:user) }

  before do
    organization.organization_memberships.create!(user: candidate, role: "member")
    stub_current_user(admin)
    stub_current_tenant("acme")
    allow(Apartment::Tenant).to receive(:current).and_return("acme")
  end

  describe "GET /moves/:move_id/members" do
    it "renders the members screen for an admin" do
      # A member other than the current admin exercises the inline role-change
      # form (the own row is locked) — the path that renders the role <select>.
      create(:move_membership, move:, user: candidate, role: "contributor")

      get move_members_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Members &amp; Roles")
      expect(response.body).to include("auto-submit")
    end

    it "forbids a contributor (admin-only screen)" do
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      get move_members_path(move)

      expect(response).to have_http_status(:forbidden)
    end

    it "404s a non-member non-disclosingly" do
      stub_current_user(create(:user))

      get move_members_path(move)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /moves/:move_id/members" do
    it "adds an Organization user as a member" do
      expect do
        post move_members_path(move), params: { member: { user_id: candidate.id, role: "viewer" } }
      end.to change { move.move_memberships.count }.by(1)

      expect(response).to redirect_to(move_members_path(move))
      expect(move.move_memberships.find_by(user: candidate).role).to eq("viewer")
    end

    it "rejects a non-Organization user (cannot share outside the Organization)" do
      outsider = create(:user)

      post move_members_path(move), params: { member: { user_id: outsider.id, role: "viewer" } }

      expect(response).to redirect_to(move_members_path(move))
      expect(move.move_memberships.find_by(user: outsider)).to be_nil
    end

    it "forbids a contributor from adding members" do
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      post move_members_path(move), params: { member: { user_id: candidate.id, role: "viewer" } }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /moves/:move_id/members/:id/update_role" do
    it "changes a member's role" do
      membership = create(:move_membership, move:, user: candidate, role: "viewer")

      patch update_role_move_member_path(move, membership), params: { member: { role: "contributor" } }

      expect(response).to redirect_to(move_members_path(move))
      expect(membership.reload.role).to eq("contributor")
    end
  end

  describe "DELETE /moves/:move_id/members/:id" do
    it "removes a member" do
      membership = create(:move_membership, move:, user: candidate, role: "viewer")

      expect do
        delete move_member_path(move, membership)
      end.to change { move.move_memberships.count }.by(-1)

      expect(response).to redirect_to(move_members_path(move))
    end
  end
end
