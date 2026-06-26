# frozen_string_literal: true

module Accounts
  # Permanently deletes a user account and everything it owns — the single
  # source of truth for what the "Delete account" danger zone promises
  # ("remove your account and all of its data"). Both self-service deletion
  # (AccountsController) and admin deletion (UsersController) go through here so
  # the guard and tenant cleanup always apply.
  #
  # The blast radius spans both schemas:
  #   - Rodauth auth tables (public.user_*_keys, omniauth identities) are removed
  #     by their `ON DELETE CASCADE` FKs when the `users` row goes.
  #   - OrganizationMembership rows (public) go via the owning org's cascade.
  #   - For every Organization the user is the SOLE member of, the registry row is
  #     destroyed and its Apartment tenant schema is dropped, taking its Moves,
  #     boxes, photos and tenant-local memberships with it.
  #
  # Scope (today): a user is the sole occupant of every organization they belong
  # to. Belonging to an org that has ANY other member — whether the user is the
  # sole owner alongside admins/members, a co-owner, or a non-owner — is
  # deliberately refused (`Failure(:owns_shared_data)`) rather than half-handled:
  # dropping a shared tenant would delete other members' data, and deleting the
  # user would strand the moves they created there (`Move#created_by` is required
  # and has no FK, so the row could not be saved afterwards). Proper handling is
  # the ownership-transfer feature; until it exists, deletion is limited to data
  # nobody else can see.
  #
  # Ordering matters: the irreversible `DROP SCHEMA` runs FIRST, then the public
  # user/org rows are deleted in one (reversible) transaction. The DROP is what
  # makes the tenant's data and MCP tokens inaccessible, so a drop that genuinely
  # fails aborts the whole deletion (`Failure(:tenant_drop_failed)`) with the
  # account fully intact — never a "deleted" account sitting in front of a live,
  # still-routable schema. Drops are gated on `schema_exists?`, so a retry after a
  # partial failure (schema gone, rows not yet deleted) is idempotent and
  # recovers. `Apartment::Tenant.drop` runs on a neutral connection, so it cannot
  # share the row-deletion transaction anyway.
  class Delete < BaseAction
    # Tenant models whose Active Storage attachments must be purged before the
    # schema is dropped: the attachment/blob tables are excluded into the public
    # schema (config/initializers/apartment.rb), so DROP SCHEMA removes the tenant
    # rows but would otherwise orphan their public attachments, blobs and stored
    # files forever (the abandoned-blob job only sweeps *unattached* blobs).
    TENANT_ATTACHMENTS = { Media => :image, LabelPrintRun => :document }.freeze

    def call(user:)
      snapshot = yield snapshot(user)
      yield ensure_only_solo_data(snapshot)
      yield drop_tenants(snapshot[:dropped_slugs])
      yield delete_records(user, snapshot)
      yield emit_event(snapshot)
      Success(snapshot[:user_id])
    end

    private

    def snapshot(user)
      solo = solo_organizations(user)
      solo_ids = solo.map(&:id)
      shared_slugs = Organization
                     .where(id: OrganizationMembership.where(user_id: user.id).select(:organization_id))
                     .where.not(id: solo_ids)
                     .pluck(:slug)

      Success(
        user_id: user.id,
        email: user.email,
        solo: solo,
        dropped_slugs: solo.map(&:slug),
        shared_slugs: shared_slugs
      )
    end

    # Orgs the user is the ONLY member of (membership count of exactly one) — no
    # other member can see them, so destroying the org and dropping its tenant
    # affects nobody else. The count is computed in SQL (AGENTS.md §1 #5), never
    # by loading rows into Ruby.
    def solo_organizations(user)
      org_ids = OrganizationMembership.where(user_id: user.id).pluck(:organization_id)
      return [] if org_ids.empty?

      solo_ids = OrganizationMembership.where(organization_id: org_ids)
                                       .group(:organization_id)
                                       .having("COUNT(*) = 1")
                                       .count
                                       .keys
      Organization.where(id: solo_ids).to_a
    end

    # Refuse to delete a user who shares any organization with another member
    # (see the class note): dropping that tenant would destroy others' data and
    # deleting the user would strand their created moves. Never triggers today
    # (solo orgs); it is the guard for when org-sharing lands without transfer.
    def ensure_only_solo_data(snapshot)
      return Failure(:owns_shared_data) if snapshot[:shared_slugs].any?

      Success()
    end

    # Drop the tenant schema(s) BEFORE deleting the public user/org rows. The
    # DROP is what makes the tenant's data and MCP tokens inaccessible (the
    # subdomain stays routable and tokens keep authenticating as long as the
    # schema exists), so a drop that genuinely fails must abort the whole
    # deletion — never report success with a live schema behind a "deleted"
    # account. Ordering is deliberate: the DROP is irreversible, the public rows
    # are reversible, so do the irreversible step first and only commit the
    # deletes once the data is provably gone.
    def drop_tenants(slugs)
      slugs.each { |slug| drop_tenant(slug) }
      Success()
    rescue ActiveRecord::ActiveRecordError, Apartment::ApartmentError => e
      Rails.logger.error("[accounts.delete] tenant drop failed: #{e.class}: #{e.message}")
      Failure(:tenant_drop_failed)
    end

    def drop_tenant(slug)
      # Idempotent: a retry after a partial failure (schema already dropped, rows
      # not yet deleted) finds nothing to drop and proceeds to the row deletion.
      return unless ActiveRecord::Base.connection.schema_exists?(slug)

      purge_attachments_in(slug)
      Apartment::Tenant.drop(slug)
    end

    # Detaching blobs is best-effort cosmetic cleanup (a failure only orphans
    # storage, never leaves a routable schema), so it must not abort the drop
    # that follows — the sanctioned broad rescue of AGENTS.md §1#4.
    def purge_attachments_in(slug)
      Apartment::Tenant.switch(slug) { purge_attachments }
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- best-effort blob cleanup must not abort the drop
      Rails.logger.error("[accounts.delete] attachment purge failed for #{slug}: #{e.class}: #{e.message}")
    end

    def delete_records(user, snapshot)
      ActiveRecord::Base.transaction do
        snapshot[:solo].each(&:destroy!) # registry rows + their memberships
        user.destroy! # auth tables cascade; org memberships already gone
      end
      Success()
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      Failure(e.message)
    end

    # Detaches each attachment (deletes the public attachment row) and enqueues
    # the blob + file purge, so dropping the tenant schema leaves nothing behind.
    # `unscoped` reaches soft-deleted rows too — Media's `default_scope { kept }`
    # would otherwise hide discarded photos and orphan their public blobs/files.
    def purge_attachments
      TENANT_ATTACHMENTS.each do |model, attachment|
        model.unscoped.find_each { |record| record.public_send(attachment).purge_later }
      end
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
