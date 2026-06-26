# frozen_string_literal: true

module Accounts
  # Permanently deletes a user account and everything it owns — the single
  # source of truth for what the "Delete account" danger zone promises
  # ("remove your account and all of its data").
  #
  # The blast radius spans both schemas:
  #   - Rodauth auth tables (public.user_*_keys, omniauth identities) are removed
  #     by their `ON DELETE CASCADE` FKs when the `users` row goes.
  #   - OrganizationMembership rows (public) go via `User#organization_memberships`
  #     `dependent: :destroy` (or the owning org's cascade) — the FK that has no
  #     ON DELETE CASCADE and was the cause of the 500.
  #   - For every Organization the user is the SOLE owner of, the registry row is
  #     destroyed and its Apartment tenant schema is dropped, taking its Moves,
  #     boxes, photos and tenant-local memberships with it.
  #
  # Scope (today): a user is the sole owner of every organization they belong to.
  # The multi-org case — a user who belongs to an org they do NOT solely own —
  # is deliberately refused (`Failure(:owns_shared_data)`) rather than half-
  # handled: deleting such a user would strand the moves they created in a
  # surviving tenant (`Move#created_by` is required and has no FK, so the row
  # cannot be saved afterwards). Proper handling is the ownership-transfer
  # feature; until it exists, account deletion is limited to self-owned data.
  #
  # Ordering matters: the relational deletes run in one transaction (so a failure
  # leaves the account fully intact), and the irreversible `DROP SCHEMA`s run
  # AFTER it commits — `Apartment::Tenant.drop` executes on a neutral connection
  # outside the transaction, so a rollback could not undo them. A drop that fails
  # post-commit only leaves an orphaned, unreferenced schema; the account is
  # already gone, which is the user's intent.
  class Delete < BaseAction
    def call(user:)
      snapshot = yield snapshot(user)
      yield ensure_only_self_owned_data(snapshot)
      yield purge(user, snapshot)
      yield emit_event(snapshot)
      Success(snapshot[:user_id])
    end

    private

    def snapshot(user)
      sole_owned = sole_owned_organizations(user)
      sole_owned_ids = sole_owned.map(&:id)
      shared_slugs = Organization
                     .where(id: OrganizationMembership.where(user_id: user.id).select(:organization_id))
                     .where.not(id: sole_owned_ids)
                     .pluck(:slug)

      Success(
        user_id: user.id,
        email: user.email,
        sole_owned: sole_owned,
        dropped_slugs: sole_owned.map(&:slug),
        shared_slugs: shared_slugs
      )
    end

    # Orgs whose only `owner` is this user — deleting the account would leave them
    # ownerless, so they are destroyed outright. The owner count is computed in
    # SQL (AGENTS.md §1 #5), never by loading rows into Ruby.
    def sole_owned_organizations(user)
      owned_ids = OrganizationMembership.where(user_id: user.id, role: "owner")
                                        .pluck(:organization_id)
      return [] if owned_ids.empty?

      sole_ids = OrganizationMembership.where(organization_id: owned_ids, role: "owner")
                                       .group(:organization_id)
                                       .having("COUNT(*) = 1")
                                       .count
                                       .keys
      Organization.where(id: sole_ids).to_a
    end

    # Refuse to delete a user who belongs to an org they do not solely own (see
    # the class note): doing so would strand their created moves in a surviving
    # tenant. Never triggers today (single-owner orgs); it is the guard for when
    # multi-org membership lands without ownership transfer.
    def ensure_only_self_owned_data(snapshot)
      return Failure(:owns_shared_data) if snapshot[:shared_slugs].any?

      Success()
    end

    def purge(user, snapshot)
      ActiveRecord::Base.transaction do
        snapshot[:sole_owned].each(&:destroy!) # registry rows + their memberships
        user.destroy! # cascades auth tables + dependent org memberships
      end

      drop_tenants(snapshot[:dropped_slugs]) # irreversible — only after the commit
      Success()
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      Failure(e.message)
    end

    def drop_tenants(slugs)
      slugs.each { |slug| Apartment::Tenant.drop(slug) }
    rescue Apartment::ApartmentError => e
      # The account and its registry rows are already committed-gone; failing to
      # drop a now-orphaned schema must not report the deletion as failed.
      Rails.logger.error("[accounts.delete] tenant drop failed: #{e.class}: #{e.message}")
    end

    def emit_event(snapshot)
      Rails.event.notify(
        "account.deleted",
        user_id: snapshot[:user_id],
        email: snapshot[:email],
        organizations_dropped: snapshot[:dropped_slugs]
      )
      Success()
    end
  end
end
