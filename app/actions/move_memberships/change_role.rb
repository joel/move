# frozen_string_literal: true

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

    def call(membership:, role:, actor:)
      role = role.to_s
      yield ensure_known_role(role)
      yield change_role(membership, role)
      yield emit_event(membership, actor)
      Success(membership)
    end

    private

    def ensure_known_role(role)
      return Failure(:invalid_role) unless MoveMembership::ROLES.include?(role)

      Success()
    end

    def change_role(membership, role)
      MoveMembership.transaction do
        next Failure(:last_admin) if demoting?(membership, role) && would_orphan_last_admin?(membership)

        membership.update!(role: role)
        Success(membership)
      end
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def demoting?(membership, role)
      membership.admin? && role != "admin"
    end

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
