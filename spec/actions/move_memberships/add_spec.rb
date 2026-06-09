# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveMemberships::Add do
  let(:admin) { create(:user) }
  let(:candidate) { create(:user) }
  let(:move) { create(:move, created_by: admin) }
  let(:organization) { Organization.create!(name: "Acme", slug: "acme-test") }

  before do
    organization.organization_memberships.create!(user: candidate, role: "member")
    # The action resolves the current Organization from the active tenant. The
    # records live in the (public) test schema; stubbing the reader does not
    # switch the schema, so queries still find them.
    allow(Apartment::Tenant).to receive(:current).and_return(organization.slug)
  end

  it "adds an existing Organization user with the given role and emits an event" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, user_id: candidate.id, role: "contributor", actor: admin)

    expect(result).to be_success
    expect(move.move_memberships.find_by(user: candidate)&.role).to eq("contributor")
    expect(Rails.event).to have_received(:notify).with(
      "move_membership.added", hash_including(move_id: move.id, user_id: candidate.id, role: "contributor")
    )
  end

  it "rejects a user who is not an Organization member, non-disclosingly" do
    stranger = create(:user)

    result = described_class.new.call(move:, user_id: stranger.id, role: "viewer", actor: admin)

    expect(result).to be_failure
    expect(result.failure).to eq(:not_found)
    expect(move.move_memberships.find_by(user: stranger)).to be_nil
  end

  it "rejects an unknown role" do
    result = described_class.new.call(move:, user_id: candidate.id, role: "captain", actor: admin)

    expect(result.failure).to eq(:invalid_role)
  end

  it "rejects adding the same user twice" do
    described_class.new.call(move:, user_id: candidate.id, role: "viewer", actor: admin)

    result = described_class.new.call(move:, user_id: candidate.id, role: "viewer", actor: admin)

    expect(result).to be_failure
  end

  # A concurrent duplicate can race past the uniqueness validation and hit the
  # unique index, raising RecordNotUnique — it must degrade to a non-disclosing
  # failure (controller → add_failed), not a 500.
  it "treats a concurrent duplicate (RecordNotUnique) as a non-disclosing failure" do
    allow(move.move_memberships).to receive(:create!)
      .and_raise(ActiveRecord::RecordNotUnique.new("PG::UniqueViolation"))

    result = described_class.new.call(move:, user_id: candidate.id, role: "viewer", actor: admin)

    expect(result).to be_failure
    expect(result.failure).to eq(:already_member)
  end
end
