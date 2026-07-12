# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveInvitations::Create do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin) }
  let(:organization) { Organization.create!(name: "Acme", slug: "acme-test") }

  before do
    allow(Apartment::Tenant).to receive(:current).and_return(organization.slug)
    allow(Rails.event).to receive(:notify)
  end

  def invite(email: "pat@example.com", role: "contributor")
    described_class.new.call(move:, email:, role:, actor: admin)
  end

  it "persists a pending invitation bound to the move, email, role, and inviter" do
    invitation = invite.value!

    expect(invitation).to be_pending
    expect(invitation.organization).to eq(organization)
    expect([invitation.move_id, invitation.email]).to eq([move.id, "pat@example.com"])
    expect(invitation.invited_by_id).to eq(admin.id)
    expect(Rails.event).to have_received(:notify).with(
      "move_invitation.created",
      hash_including(move_id: move.id, email: "pat@example.com", role: "contributor", actor_id: admin.id)
    )
  end

  it "stores only the token digest and mails the matching raw token" do
    result = nil
    # The test queue adapter is :inline, so deliver_later delivers synchronously.
    expect { result = invite }.to change(ActionMailer::Base.deliveries, :size).by(1)

    invitation = result.value!
    expect(invitation.token_digest).to match(/\A\h{64}\z/)
    # The mailed link carries the raw token whose digest is the persisted one.
    body = ActionMailer::Base.deliveries.last.text_part.body.to_s
    raw = body[/invitations\?token=([A-Za-z0-9_-]+)/, 1]
    expect(MoveInvitation.digest(raw)).to eq(invitation.token_digest)
  end

  it "rejects a malformed email without disclosing anything else" do
    expect(invite(email: "not-an-email").failure).to eq(:invalid_email)
    expect(invite(email: "").failure).to eq(:invalid_email)
  end

  it "rejects an unknown role" do
    expect(invite(role: "owner").failure).to eq(:invalid_role)
  end

  it "rejects an email already on the Move, case-insensitively" do
    member = create(:user, email: "pat@example.com")
    move.move_memberships.create!(user: member, role: "viewer")

    expect(invite(email: "Pat@Example.com").failure).to eq(:already_member)
  end

  it "invites an email with an existing account that is not on the Move" do
    create(:user, email: "pat@example.com")

    expect(invite).to be_success
  end

  it "rejects a duplicate live invitation and points at resend" do
    invite

    result = invite

    expect(result.failure).to eq(:already_invited)
  end

  it "allows a fresh invitation after the previous one was revoked" do
    first = invite.value!
    MoveInvitations::Revoke.new.call(invitation: first, actor: admin)

    expect(invite).to be_success
  end
end
