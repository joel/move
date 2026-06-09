# frozen_string_literal: true

module MoveMemberships
  # Removes a member from a Move (F1, D11). Admin-only (enforced in the
  # controller via MovePolicy#manage_members?).
  #
  # Guards against removing the Move's last admin — a Move must always retain at
  # least one admin who can manage its members.
  class Remove < BaseAction
    def call(membership:, actor:)
      yield ensure_admin_remains(membership)
      details = capture(membership)
      yield destroy(membership)
      yield emit_event(details, actor)
      Success(details)
    end

    private

    def ensure_admin_remains(membership)
      return Success() unless membership.admin?
      return Success() if other_admins?(membership)

      Failure(:last_admin)
    end

    def other_admins?(membership)
      membership.move.move_memberships
                .where(role: "admin")
                .where.not(id: membership.id)
                .exists?
    end

    # Capture identifiers before destroy! — the record is gone afterwards.
    def capture(membership)
      { move_id: membership.move_id, user_id: membership.user_id, role: membership.role }
    end

    def destroy(membership)
      membership.destroy!
      Success()
    rescue ActiveRecord::RecordNotDestroyed => e
      Failure(e.record.errors)
    end

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
