# frozen_string_literal: true

# pack_public: true -- public API of packs/move_invitations: revokes a pending invitation (InvitationsController).
# Kept in its layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module MoveInvitations
  # Revoke a pending invitation (Phase D14, #608): the emailed link dies
  # immediately. Atomic by construction — the guarded update contends with a
  # racing accept on the same WHERE, so exactly one wins and a revoke can never
  # land on an already-accepted invitation (membership removal is F1's Remove).
  class Revoke < BaseAction
    #: (invitation: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(invitation:, actor:)
      yield claim(invitation)
      yield emit_event(invitation, actor)
      Success(invitation.reload)
    end

    private

    #: (untyped invitation) -> Dry::Monads::Result[untyped, untyped]
    def claim(invitation)
      # rubocop:disable Rails/SkipsModelValidations -- atomic single-winner
      # transition: the WHERE lets exactly one of {revoke, accept} claim the row.
      revoked = MoveInvitation
                .where(id: invitation.id, accepted_at: nil, revoked_at: nil)
                .update_all(revoked_at: Time.current)
      # rubocop:enable Rails/SkipsModelValidations
      revoked == 1 ? Success() : Failure(:not_pending)
    end

    #: (untyped invitation, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(invitation, actor)
      Rails.event.notify(
        "move_invitation.revoked",
        move_id: invitation.move_id,
        invitation_id: invitation.id,
        email: invitation.email,
        actor_id: actor&.id
      )
      Success()
    end
  end
end
