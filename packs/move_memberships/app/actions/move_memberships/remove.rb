# frozen_string_literal: true

# pack_public: true -- public API of packs/move_memberships: removes a member (MembersController).
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module MoveMemberships
  # Removes a member from a Move (F1, D11). Admin-only (enforced in the
  # controller via MovePolicy#manage_members?).
  #
  # The last-admin guard and the destroy run in one transaction with a row lock
  # (AdminGuard) so concurrent admin removals cannot both slip past the check.
  class Remove < BaseAction
    include AdminGuard
    include TokenRevocation

    #: (membership: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(membership:, actor:)
      details = capture(membership)
      revoked = yield remove(membership)
      yield emit_event(details, actor)
      emit_token_revocations(revoked, actor)
      Success(details)
    end

    private

    #: (untyped membership) -> Dry::Monads::Result[untyped, untyped]
    def remove(membership)
      MoveMembership.transaction do
        next Failure(:last_admin) if would_orphan_last_admin?(membership)

        # A removed member holds no role, so revoke their MCP tokens in the same
        # transaction (deprovisioning — see TokenRevocation).
        revoked = revoke_member_tokens(membership.move, membership.user_id)
        membership.destroy!
        Success(revoked)
      end
    rescue ActiveRecord::RecordNotDestroyed => e
      Failure(e.record.errors)
    end

    # Capture identifiers before destroy! — the record is gone afterwards.

    #: (untyped membership) -> Hash[Symbol, untyped]
    def capture(membership)
      { move_id: membership.move_id, user_id: membership.user_id, role: membership.role }
    end

    #: (untyped details, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(details, actor)
      Rails.event.notify(
        "move_membership.removed",
        move_id: details[:move_id],
        user_id: details[:user_id],
        role: details[:role],
        actor_id: actor&.id
      )
      Success()
    end
  end
end
