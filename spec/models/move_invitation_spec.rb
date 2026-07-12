# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveInvitation do
  describe "validations" do
    it "requires a role from the MoveMembership set" do
      invitation = build(:move_invitation, role: "owner")
      expect(invitation).not_to be_valid
      expect(invitation.errors[:role]).to be_present
    end

    it "enforces one live invitation per (move, email), case-insensitively" do
      existing = create(:move_invitation, email: "Pat@Example.com")

      dup = build(:move_invitation, move_id: existing.move_id, email: "pat@example.com",
                                    organization: existing.organization)
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a fresh invitation once the previous one is terminal" do
      existing = create(:move_invitation, :revoked, email: "pat@example.com")

      fresh = build(:move_invitation, move_id: existing.move_id, email: "pat@example.com",
                                      organization: existing.organization)
      expect(fresh.save).to be(true)
    end
  end

  describe "token handling" do
    it "digests to the SHA-256 hex of the raw token, never the raw value" do
      raw = described_class.generate_raw_token
      expect(described_class.digest(raw)).to eq(Digest::SHA256.hexdigest(raw))
      expect(described_class.digest(raw)).not_to eq(raw)
    end
  end

  describe "state predicates and scopes" do
    it "is pending only while unaccepted, unrevoked, and unexpired" do
      expect(create(:move_invitation)).to be_pending
      expect(create(:move_invitation, :accepted)).not_to be_pending
      expect(create(:move_invitation, :revoked)).not_to be_pending
      expect(create(:move_invitation, :expired)).not_to be_pending
    end

    it "scopes pending to live rows only" do
      live = create(:move_invitation)
      create(:move_invitation, :accepted)
      create(:move_invitation, :revoked)
      create(:move_invitation, :expired)

      expect(described_class.pending).to contain_exactly(live)
    end

    it "scopes purgeable to terminal rows past retention" do
      stale_accepted = create(:move_invitation, accepted_at: (MoveInvitation::RETENTION + 1.day).ago)
      stale_revoked = create(:move_invitation, revoked_at: (MoveInvitation::RETENTION + 1.day).ago)
      stale_expired = create(:move_invitation, expires_at: (MoveInvitation::RETENTION + 1.day).ago)
      create(:move_invitation) # live
      create(:move_invitation, :accepted) # terminal but within retention

      expect(described_class.purgeable)
        .to contain_exactly(stale_accepted, stale_revoked, stale_expired)
    end
  end
end
