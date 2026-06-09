# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveMemberships::ChangeRole do
  let(:move) { create(:move) }
  let(:admin) { move.move_memberships.find_by(role: "admin").user }
  let(:other) { create(:user) }

  it "changes a member's role and emits an event" do
    membership = create(:move_membership, move:, user: other, role: "viewer")
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(membership:, role: "contributor", actor: admin)

    expect(result).to be_success
    expect(membership.reload.role).to eq("contributor")
    expect(Rails.event).to have_received(:notify).with(
      "move_membership.role_changed", hash_including(user_id: other.id, role: "contributor")
    )
  end

  it "refuses to demote the last admin" do
    membership = move.move_memberships.find_by(role: "admin")

    result = described_class.new.call(membership:, role: "viewer", actor: admin)

    expect(result.failure).to eq(:last_admin)
    expect(membership.reload.role).to eq("admin")
  end

  it "allows demoting an admin when another admin remains" do
    create(:move_membership, move:, user: other, role: "admin")
    membership = move.move_memberships.find_by(user: admin)

    result = described_class.new.call(membership:, role: "viewer", actor: other)

    expect(result).to be_success
    expect(membership.reload.role).to eq("viewer")
  end

  it "rejects an unknown role" do
    membership = create(:move_membership, move:, user: other, role: "viewer")

    result = described_class.new.call(membership:, role: "captain", actor: admin)

    expect(result.failure).to eq(:invalid_role)
  end
end
