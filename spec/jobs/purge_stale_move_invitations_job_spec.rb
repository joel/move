# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeStaleMoveInvitationsJob do
  it "deletes terminal invitations past retention but keeps live and recent ones" do
    stale = create(:move_invitation, revoked_at: (MoveInvitation::RETENTION + 1.day).ago)
    recent_terminal = create(:move_invitation, :accepted)
    live = create(:move_invitation)

    described_class.new.perform

    expect(MoveInvitation.exists?(stale.id)).to be(false)
    expect(MoveInvitation.exists?(recent_terminal.id)).to be(true)
    expect(MoveInvitation.exists?(live.id)).to be(true)
  end
end
