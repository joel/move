# frozen_string_literal: true

module MoveMemberships
  # Removes a member from a Move (F1, D11). Admin-only (enforced in the
  # controller via MovePolicy#manage_members?).
  #
  # The last-admin guard and the destroy run in one transaction with a row lock
  # (AdminGuard) so concurrent admin removals cannot both slip past the check.
  class Remove < BaseAction
    include AdminGuard

    def call(membership:, actor:)
      details = capture(membership)
      yield remove(membership)
      yield emit_event(details, actor)
      Success(details)
    end

    private

    def remove(membership)
      MoveMembership.transaction do
        next Failure(:last_admin) if would_orphan_last_admin?(membership)

        membership.destroy!
        Success()
      end
    rescue ActiveRecord::RecordNotDestroyed => e
      Failure(e.record.errors)
    end

    # Capture identifiers before destroy! — the record is gone afterwards.
    def capture(membership)
      { move_id: membership.move_id, user_id: membership.user_id, role: membership.role }
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
