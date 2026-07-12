# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveInvitations::Resend do
  let(:admin) { create(:user) }

  before { allow(Rails.event).to receive(:notify) }

  it "rotates the token and expiry in place and re-mails" do
    invitation = create(:move_invitation, expires_at: 1.hour.from_now)
    old_digest = invitation.token_digest

    result = nil
    expect { result = described_class.new.call(invitation:, actor: admin) }
      .to change(ActionMailer::Base.deliveries, :size).by(1)

    expect(result).to be_success
    invitation.reload
    expect(invitation.token_digest).not_to eq(old_digest)
    expect(invitation.expires_at).to be > 6.days.from_now
    expect(Rails.event).to have_received(:notify)
      .with("move_invitation.resent", hash_including(invitation_id: invitation.id))
  end

  it "revives an expired-but-unaccepted invitation (the pending row blocks a fresh invite)" do
    invitation = create(:move_invitation, :expired)

    result = described_class.new.call(invitation:, actor: admin)

    expect(result).to be_success
    expect(invitation.reload).to be_pending
  end

  it "refuses to rotate an accepted or revoked invitation" do
    expect(described_class.new.call(invitation: create(:move_invitation, :accepted), actor: admin).failure)
      .to eq(:not_pending)
    expect(described_class.new.call(invitation: create(:move_invitation, :revoked), actor: admin).failure)
      .to eq(:not_pending)
  end
end
