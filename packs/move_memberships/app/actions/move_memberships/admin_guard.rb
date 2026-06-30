# frozen_string_literal: true

module MoveMemberships
  # Shared guard that keeps a Move from losing its last admin (F1, D11).
  #
  # The check must be serialized with the mutation: without a lock, two admins
  # removing themselves (or demoting each other) concurrently can both pass a
  # plain existence check and then commit, leaving the Move with zero admins.
  # `would_orphan_last_admin?` locks the Move's admin rows FOR UPDATE, so the
  # second transaction blocks until the first commits and then re-reads the
  # current admin set. Call it inside a transaction; the lock releases on
  # commit/rollback.
  module AdminGuard
    private

    # True if +membership+ ceasing to be an admin (removal or demotion) would
    # leave the Move with no admin. Locks the full admin set — including
    # +membership+ — so concurrent admin changes contend on the same rows.
    def would_orphan_last_admin?(membership)
      return false unless membership.admin?

      admin_ids = membership.move.move_memberships
                            .where(role: "admin")
                            .lock("FOR UPDATE").ids
      (admin_ids - [membership.id]).empty?
    end
  end
end
