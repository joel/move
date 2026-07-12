# frozen_string_literal: true

# pack_public: true -- public API of packs/move_invitations: re-sends an invitation (InvitationsController).
# Kept in its layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module MoveInvitations
  # Re-send an invitation (Phase D14, #608): rotates the token digest and the
  # expiry IN PLACE on the same row — the old emailed link dies instantly, the
  # one-live-invitation-per-(move, email) invariant holds trivially, and an
  # expired-but-unaccepted invitation is revived rather than blocking a fresh
  # invite on the partial unique index. The guarded update makes the rotate
  # atomic against a racing accept or revoke.
  class Resend < BaseAction
    #: (invitation: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(invitation:, actor:)
      raw = MoveInvitation.generate_raw_token
      yield rotate(invitation, raw)
      yield emit_event(invitation, actor)
      deliver(invitation, raw)
      Success(invitation.reload)
    end

    private

    #: (untyped invitation, untyped raw) -> Dry::Monads::Result[untyped, untyped]
    def rotate(invitation, raw)
      # rubocop:disable Rails/SkipsModelValidations -- atomic rotate: only an
      # un-accepted, un-revoked row takes the new token; a racing accept/revoke
      # wins or loses cleanly on the same WHERE.
      rotated = MoveInvitation
                .where(id: invitation.id, accepted_at: nil, revoked_at: nil)
                .update_all(
                  token_digest: MoveInvitation.digest(raw),
                  expires_at: MoveInvitation::TTL.from_now,
                  updated_at: Time.current
                )
      # rubocop:enable Rails/SkipsModelValidations
      rotated == 1 ? Success() : Failure(:not_pending)
    end

    #: (untyped invitation, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(invitation, actor)
      Rails.event.notify(
        "move_invitation.resent",
        move_id: invitation.move_id,
        invitation_id: invitation.id,
        email: invitation.email,
        actor_id: actor&.id
      )
      Success()
    end

    #: (untyped invitation, untyped raw) -> void
    def deliver(invitation, raw)
      MoveInvitationMailer.invite(invitation_id: invitation.id, raw_token: raw).deliver_later
    end
  end
end
