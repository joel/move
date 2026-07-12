# frozen_string_literal: true

# An email invitation to join a Move (Phase D14, #608): a Move admin invites any
# address with a role; the recipient proves mailbox ownership by authenticating
# as that email (passwordless), and acceptance creates the OrganizationMembership
# before the MoveMembership.
#
# Lives in the `public` schema (excluded Apartment model) because the accept
# flow runs on the apex host, where no tenant is active — the emailed token must
# resolve before the invitee can reach any tenant. Only the SHA-256 digest is
# persisted (the raw token travels once, in the invitation email), mirroring
# SessionHandoffToken.
#
# Create/revoke/resend/accept live in app/actions/move_invitations; this model
# stays persistence-focused (digesting, state predicates, scopes).
class MoveInvitation < ApplicationRecord
  include DigestedToken

  # How long an invitation link stays valid. Long enough to survive a weekend
  # inbox; resend rotates the token and restarts the clock.
  TTL = 7.days

  # Raw tokens are urlsafe-base64 (43 chars for 32 bytes); anything outside this
  # shape is rejected before digesting — the auth-flow carry (hidden fields,
  # emailed links) only ever forwards a value matching it.
  TOKEN_FORMAT = /\A[A-Za-z0-9_-]{1,128}\z/

  # How long terminal rows (accepted/revoked/expired) are kept before the sweep
  # reaps them — the activity feed is the durable audit trail.
  RETENTION = 30.days

  belongs_to :organization
  # invited_by references public.users; nullified when that user is deleted.
  belongs_to :invited_by, class_name: "User", optional: true, inverse_of: false

  validates :move_id, presence: true
  validates :email, presence: true
  validates :role, inclusion: { in: MoveMembership::ROLES }
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  # Live invitations: not yet accepted or revoked, clock still running.
  scope :pending, -> { where(accepted_at: nil, revoked_at: nil).where(expires_at: Time.current..) }

  # The Members-page pending list: every un-terminal invitation for the Move,
  # newest first (recency — UX rule #2). Deliberately INCLUDES expired rows —
  # they still hold the one-live-invitation partial unique index, so they must
  # stay visible (Expired tint) and revivable via Resend, never an invisible
  # dead end blocking a re-invite.
  scope :open_for, lambda { |move_id|
    where(accepted_at: nil, revoked_at: nil).where(move_id: move_id).order(created_at: :desc)
  }

  # Rows the nightly sweep (PurgeStaleMoveInvitationsJob) reaps: anything
  # terminal (accepted, revoked, or expired-unaccepted) older than RETENTION.
  scope :purgeable, lambda {
    cutoff = RETENTION.ago
    where(accepted_at: ...cutoff)
      .or(where(revoked_at: ...cutoff))
      .or(where(accepted_at: nil, revoked_at: nil).where(expires_at: ...cutoff))
  }

  #: () -> bool
  def expired?
    expires_at <= Time.current
  end

  #: () -> bool
  def accepted?
    accepted_at.present?
  end

  #: () -> bool
  def revoked?
    revoked_at.present?
  end

  #: () -> bool
  def pending?
    !accepted? && !revoked? && !expired?
  end
end
