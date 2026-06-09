# frozen_string_literal: true

module MoveMemberships
  # Changes a member's role on a Move (F1, D11). Admin-only (enforced in the
  # controller via MovePolicy#manage_members?). Concurrent changes are
  # last-action-wins.
  #
  # Guards against demoting the Move's last admin: a Move must always retain at
  # least one admin, or no one could manage its members.
  class ChangeRole < BaseAction
    def call(membership:, role:, actor:)
      role = role.to_s
      yield ensure_known_role(role)
      yield ensure_admin_remains(membership, role)
      yield update_role(membership, role)
      yield emit_event(membership, actor)
      Success(membership)
    end

    private

    def ensure_known_role(role)
      return Failure(:invalid_role) unless MoveMembership::ROLES.include?(role)

      Success()
    end

    # Block demoting the last remaining admin.
    def ensure_admin_remains(membership, role)
      return Success() unless membership.admin? && role != "admin"
      return Success() if other_admins?(membership)

      Failure(:last_admin)
    end

    def other_admins?(membership)
      membership.move.move_memberships
                .where(role: "admin")
                .where.not(id: membership.id)
                .exists?
    end

    def update_role(membership, role)
      membership.update!(role: role)
      Success(membership)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
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
