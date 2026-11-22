# frozen_string_literal: true

require "rails_helper"

# Real-lock proof for #366 (the unit specs in delete_spec/accept_spec pin the
# ORDER of the steps; this pins that the lock is actually HELD). Both
# Accounts::Delete's teardown and MoveInvitations::Accept's org-join take
# `SELECT … FOR UPDATE` on the same `organizations` row, so whichever is inside
# its critical section makes the other wait. A second connection probes the row
# with NOWAIT from inside each critical section: a lock error means the lock is
# held there. Deterministic, no sleeps.
#
# Transactional fixtures are off for this file: the probe runs on another
# connection, which cannot see rows the test transaction never committed.
RSpec.describe Accounts::Delete do # org-row lock shared with MoveInvitations::Accept (#366)
  self.use_transactional_tests = false

  let(:organization) { Organization.create!(name: "Lock Org", slug: "lock-366") }
  let(:owner) { create(:user) }
  let(:invitee) { create(:user) }

  before do
    OrganizationMembership.create!(organization: organization, user: owner, role: "owner")
    allow(Apartment::Tenant).to receive(:switch).and_yield
    allow(ActiveRecord::Base.connection).to receive(:schema_exists?).and_call_original
    allow(ActiveRecord::Base.connection).to receive(:schema_exists?).with("lock-366").and_return(true)
    allow(Rails.event).to receive(:notify)
  end

  after do
    OrganizationMembership.where(user_id: [owner.id, invitee.id]).delete_all
    Organization.where(slug: "lock-366").destroy_all
    User.where(id: [owner.id, invitee.id]).destroy_all
  end

  # Tries to take the same row lock from another connection without waiting.
  # Returns true when it is already held elsewhere.
  def locked_elsewhere?(org_id)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.transaction do
          conn.select_value(
            "SELECT id FROM organizations WHERE id = #{conn.quote(org_id)} FOR UPDATE NOWAIT"
          )
        end
        false
      rescue ActiveRecord::LockWaitTimeout
        true
      end
    end.value
  end

  it "holds the org row lock while Accounts::Delete drops the tenant" do
    held_at_drop = nil
    allow(Apartment::Tenant).to receive(:drop) { held_at_drop = locked_elsewhere?(organization.id) }

    expect(described_class.new.call(user: owner)).to be_success
    expect(held_at_drop).to be(true)
    expect(locked_elsewhere?(organization.id)).to be(false) # released (row gone) after commit
  end

  it "holds the same org row lock while MoveInvitations::Accept joins the org" do
    held_at_join = nil
    allow(OrganizationMembership).to receive(:find_or_create_by!).and_wrap_original do |original, **kw, &blk|
      held_at_join = locked_elsewhere?(organization.id)
      original.call(**kw, &blk)
    end

    result = MoveInvitations::Accept.new.send(:join_organization, organization, invitee)

    expect(result).to be_success
    expect(held_at_join).to be(true)
    expect(locked_elsewhere?(organization.id)).to be(false)
  end
end
