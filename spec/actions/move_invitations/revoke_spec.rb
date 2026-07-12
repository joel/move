# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveInvitations::Revoke do
  let(:admin) { create(:user) }

  before { allow(Rails.event).to receive(:notify) }

  it "revokes a pending invitation and emits an event" do
    invitation = create(:move_invitation)

    result = described_class.new.call(invitation:, actor: admin)

    expect(result).to be_success
    expect(invitation.reload).to be_revoked
    expect(Rails.event).to have_received(:notify).with(
      "move_invitation.revoked",
      hash_including(invitation_id: invitation.id, email: invitation.email, actor_id: admin.id)
    )
  end

  it "cannot revoke an already-accepted invitation" do
    invitation = create(:move_invitation, :accepted)

    result = described_class.new.call(invitation:, actor: admin)

    expect(result.failure).to eq(:not_pending)
    expect(invitation.reload).not_to be_revoked
  end

  it "is a no-op failure on an already-revoked invitation" do
    invitation = create(:move_invitation, :revoked)

    expect(described_class.new.call(invitation:, actor: admin).failure).to eq(:not_pending)
  end
end
