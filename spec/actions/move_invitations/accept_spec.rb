# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveInvitations::Accept do
  let(:admin) { create(:user) }
  let(:invitee) { create(:user, email: "pat@example.com") }
  let(:move) { create(:move, created_by: admin) }
  let(:organization) { Organization.create!(name: "Acme", slug: "acme-test") }
  let!(:invitation) do
    create(:move_invitation,
           organization:, move_id: move.id, email: "pat@example.com",
           invited_by: admin, token_digest: MoveInvitation.digest(raw_token))
  end

  # A method, not a let — keeps the memoized-helper count at five, and let!
  # blocks resolve it like any helper.
  define_method(:raw_token) { "d14-test-raw-token" }

  before do
    # The joins run on the apex; the tenant switch resolves against the (public)
    # test schema, and MoveMemberships::Add reads the tenant name from current.
    allow(Apartment::Tenant).to receive(:switch).and_yield
    allow(Apartment::Tenant).to receive(:current).and_return(organization.slug)
    allow(Rails.event).to receive(:notify)
  end

  def accept(raw: nil, user: nil)
    described_class.new.call(raw_token: raw || raw_token, user: user || invitee)
  end

  it "claims the invitation, joins the organization THEN the move, and emits" do
    result = accept

    expect(result).to be_success
    expect(result.value![:move_id]).to eq(move.id)
    expect(invitation.reload).to be_accepted
    expect(OrganizationMembership.find_by(organization:, user: invitee)&.role).to eq("member")
    expect(move.move_memberships.find_by(user: invitee)&.role).to eq("contributor")
    expect(Rails.event).to have_received(:notify)
      .with("move_invitation.accepted", hash_including(invitation_id: invitation.id, actor_id: invitee.id))
  end

  it "binds acceptance to the invited email, case-insensitively" do
    upper = create(:user, email: "PAT@example.com")
    other = create(:user, email: "other@example.com")

    expect(accept(user: other).failure).to eq(:mismatch)
    expect(accept(user: upper)).to be_success
  end

  it "rejects unknown, blank, revoked, and expired tokens" do
    expect(accept(raw: "").failure).to eq(:invalid)
    expect(accept(raw: "nope").failure).to eq(:invalid)

    invitation.update!(revoked_at: Time.current)
    expect(accept.failure).to eq(:revoked)

    invitation.update!(revoked_at: nil, expires_at: 1.minute.ago)
    expect(accept.failure).to eq(:expired)
  end

  it "re-running for the matching user resumes the idempotent joins (crash/two tabs)" do
    accept
    move.move_memberships.find_by(user: invitee).destroy! # simulate a crash between claim and join

    result = accept

    expect(result).to be_success
    expect(move.move_memberships.find_by(user: invitee)&.role).to eq("contributor")
  end

  it "skips the org-join idempotently for an existing organization member" do
    organization.organization_memberships.create!(user: invitee, role: "admin")

    result = accept

    expect(result).to be_success
    # The pre-existing role is untouched — the join is find-or-create, not upsert.
    expect(OrganizationMembership.find_by(organization:, user: invitee).role).to eq("admin")
  end

  it "treats an already-held move membership as success" do
    organization.organization_memberships.create!(user: invitee, role: "member")
    move.move_memberships.create!(user: invitee, role: "viewer")

    expect(accept).to be_success
    expect(move.move_memberships.find_by(user: invitee).role).to eq("viewer")
  end

  it "fails without any org-join when the Move is gone" do
    move.destroy!

    result = accept

    expect(result.failure).to eq(:gone)
    expect(invitation.reload).not_to be_accepted
    expect(OrganizationMembership.exists?(organization:, user: invitee)).to be(false)
  end

  it "refuses to accept onto an archived (read-only) Move, leaving the invite unclaimed" do
    move.update!(status: "archived")

    result = accept

    expect(result.failure).to eq(:gone)
    expect(invitation.reload).not_to be_accepted # revivable if the Move is un-archived
    expect(OrganizationMembership.exists?(organization:, user: invitee)).to be(false)
  end
end
