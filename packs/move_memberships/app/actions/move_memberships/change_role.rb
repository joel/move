# frozen_string_literal: true

# pack_public: true -- public API of packs/move_memberships: changes a member's role (MembersController).
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module MoveMemberships
  # Changes a member's role on a Move (F1, D11). Admin-only (enforced in the
  # controller via MovePolicy#manage_members?). Concurrent role changes are
  # last-action-wins.
  #
  # Demoting the Move's last admin is blocked: the guard and the update run in one
  # transaction with a row lock (AdminGuard) so concurrent demotions cannot both
  # slip past the check and leave the Move with no admin.
  class ChangeRole < BaseAction
    include AdminGuard
    include TokenRevocation

    #: (membership: untyped, role: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(membership:, role:, actor:)
      role = role.to_s
      yield ensure_known_role(role)
      revoked = yield change_role(membership, role)
      yield emit_event(membership, actor)
      emit_token_revocations(revoked, actor)
      Success(membership)
    end

    private

    #: (untyped role) -> Dry::Monads::Result[untyped, untyped]
    def ensure_known_role(role)
      return Failure(:invalid_role) unless MoveMembership::ROLES.include?(role)

      Success()
    end

    #: (untyped membership, untyped role) -> Dry::Monads::Result[untyped, untyped]
    def change_role(membership, role)
      MoveMembership.transaction do
        next Failure(:last_admin) if demoting?(membership, role) && would_orphan_last_admin?(membership)

        # Demotion out of admin removes the token-management privilege, so revoke
        # this member's MCP tokens in the same transaction (deprovisioning — see
        # TokenRevocation). Returns [] when the change isn't a demotion.
        revoked = demoting?(membership, role) ? revoke_member_tokens(membership.move, membership.user_id) : []
        membership.update!(role: role)
        Success(revoked)
      end
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped membership, untyped role) -> bool
    def demoting?(membership, role)
      membership.admin? && role != "admin"
    end

    #: (untyped membership, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(membership, actor)
      Rails.event.notify(
        "move_membership.role_changed",
        move_id: membership.move_id,
        user_id: membership.user_id,
        role: membership.role,
        actor_id: actor&.id
      )
      Success()
    end
  end
end
