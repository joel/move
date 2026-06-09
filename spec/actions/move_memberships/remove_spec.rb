# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveMemberships::Remove do
  let(:move) { create(:move) }
  let(:admin) { move.move_memberships.find_by(role: "admin").user }
  let(:other) { create(:user) }

  it "removes a member and emits an event" do
    membership = create(:move_membership, move:, user: other, role: "contributor")
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(membership:, actor: admin)

    expect(result).to be_success
    expect(move.move_memberships.find_by(user: other)).to be_nil
    expect(Rails.event).to have_received(:notify).with(
      "move_membership.removed", hash_including(move_id: move.id, user_id: other.id, role: "contributor")
    )
  end

  it "refuses to remove the last admin" do
    membership = move.move_memberships.find_by(role: "admin")

    result = described_class.new.call(membership:, actor: admin)

    expect(result.failure).to eq(:last_admin)
    expect(membership.reload).to be_present
  end

  it "removes an admin when another admin remains" do
    create(:move_membership, move:, user: other, role: "admin")
    membership = move.move_memberships.find_by(user: admin)

    result = described_class.new.call(membership:, actor: other)

    expect(result).to be_success
    expect(move.move_memberships.find_by(user: admin)).to be_nil
  end
end
