# frozen_string_literal: true

# pack_public: true -- public API of packs/accounts: Accounts/UsersController call Accounts::Delete.
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

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
  #   - SessionHandoffToken rows (public, #280) have no FK to users, so they are
  #     deleted explicitly (they would otherwise linger until the purge sweep).
  #   - For every Organization the user is the SOLE member of, the registry row is
  #     destroyed and its Apartment tenant schema is dropped, taking its Moves,
  #     boxes, photos and tenant-local memberships with it.
  #
  # Scope: only organizations the user is the sole occupant of are deleted.
  # Belonging to an org that has ANY other member — whether the user is the
  # sole owner alongside admins/members, a co-owner, or a non-owner — is
  # deliberately refused (`Failure(:owns_shared_data)`) rather than half-handled:
  # dropping a shared tenant would delete other members' data, and deleting the
  # user would strand the moves they created there (`Move#created_by` is required
  # and has no FK, so the row could not be saved afterwards). Proper handling is
  # the ownership-transfer feature; until it exists, deletion is limited to data
  # nobody else can see.
  #
  # Ordering matters, and each solo org is torn down as an irreversible unit
  # BEFORE the account row is deleted: capture its attachment blobs, drop the
  # schema, purge those blobs, then delete the public org row — repeated per org,
  # then finally delete the user. Three properties fall out of this order:
  #   - A drop that genuinely fails aborts the whole deletion
  #     (`Failure(:tenant_drop_failed)`) — never a "deleted" account sitting in
  #     front of a live, still-routable schema (the subdomain resolves and MCP
  #     tokens authenticate as long as the schema exists).
  #   - Deleting each org row immediately after its own schema drops means a
  #     mid-loop failure never leaves an org row pointing at a missing schema;
  #     already-torn-down orgs stay gone, so a retry resumes cleanly (drops are
  #     gated on `schema_exists?`).
  #   - Blobs are purged only AFTER a successful drop, so a failed drop never
  #     strips media/label files from a tenant that survives.
  #
  # Concurrency (#366): since invitations (#608), MoveInvitations::Accept can add
  # a member to an EXISTING org, so the snapshot's "solo" verdict can go stale
  # before the drop. Each org's teardown therefore runs in its own transaction
  # that first takes `SELECT … FOR UPDATE` on the org's public row, the same lock
  # Accept takes around its org-join, and rechecks under it that no other member
  # exists. Accept either commits its membership first (the recheck sees it and
  # the teardown refuses with `:organization_became_shared`) or waits and then
  # finds the org gone (`:gone`). On a single-server Apartment setup `drop` runs
  # `DROP SCHEMA` on this same connection, so the drop and the org-row delete
  # commit or roll back together. Blobs are purged only after the commit.
  class Delete < BaseAction
    # Tenant models whose Active Storage attachments must be purged when the
    # schema is dropped: the attachment/blob tables are excluded into the public
    # schema (config/initializers/apartment.rb), so DROP SCHEMA removes the tenant
    # rows but would otherwise orphan their public attachments, blobs and stored
    # files forever (the abandoned-blob job only sweeps *unattached* blobs).
    TENANT_ATTACHMENTS = { Media => :image, LabelPrintRun => :document, InsuranceDossierRun => :document }.freeze

    #: (user: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(user:)
      snapshot = yield snapshot(user)
      yield ensure_only_solo_data(snapshot)
      yield teardown_solo_orgs(snapshot[:solo], user)
      yield delete_user(user)
      yield emit_event(snapshot)
      Success(snapshot[:user_id])
    end

    private

    #: (untyped user) -> Dry::Monads::Success[untyped]
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

    #: (untyped user) -> Array[untyped]
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
    # deleting the user would strand their created moves. Since invitations
    # (#608) this DOES trigger — for the invitee and the inviting owner alike —
    # until leave / transfer-ownership exists (#366). It is a fast pre-check;
    # the authoritative recheck runs under the org row lock at teardown.

    #: (untyped snapshot) -> Dry::Monads::Result[untyped, untyped]
    def ensure_only_solo_data(snapshot)
      return Failure(:owns_shared_data) if snapshot[:shared_slugs].any?

      Success()
    end

    # Tear each solo org down as an irreversible unit. A genuine drop failure
    # aborts the whole deletion; orgs already torn down stay gone, so a retry
    # resumes from where it stopped. An org that gained a member since the
    # snapshot stops the loop the same way (nothing of THAT org is touched).

    #: (untyped orgs, untyped user) -> Dry::Monads::Result[untyped, untyped]
    def teardown_solo_orgs(orgs, user)
      orgs.each do |org|
        return Failure(:organization_became_shared) if teardown_solo_org(org, user) == :shared
      end
      Success()
    rescue ActiveRecord::ActiveRecordError, Apartment::ApartmentError => e
      Rails.logger.error("[accounts.delete] solo org teardown failed: #{e.class}: #{e.message}")
      Failure(:tenant_drop_failed)
    end

    # One org, one transaction, under the org row lock (see the class note).
    # Returns :shared when another member joined after the snapshot, else :done.

    #: (untyped org, untyped user) -> Symbol
    def teardown_solo_org(org, user)
      attachment_ids = [] #: Array[untyped]
      # On Organization's connection: the lock, the recheck, the drop and the row
      # delete must all share ONE transaction (Apartment schema-qualifies excluded
      # models onto the same connection it runs DROP SCHEMA on).
      outcome = Organization.transaction do
        locked = Organization.lock.find_by(id: org.id)
        if locked.nil?
          :done # a concurrent teardown already removed it
        elsif other_member?(locked, user)
          :shared
        else
          attachment_ids = drop_tenant(locked)
          locked.destroy! # public row, once its schema is provably gone
          :done
        end
      end
      purge_attachments(attachment_ids) # only after the commit — never strip a surviving tenant
      outcome
    end

    #: (untyped org, untyped user) -> bool
    def other_member?(org, user)
      OrganizationMembership.where(organization_id: org.id).where.not(user_id: user.id).exists?
    end

    # Idempotent on retry: if the schema is already gone (dropped on a prior
    # attempt that failed later), there is nothing to capture or drop.

    #: (untyped org) -> Array[untyped]
    def drop_tenant(org)
      return [] unless ActiveRecord::Base.connection.schema_exists?(org.slug)

      attachment_ids = capture_attachment_ids(org.slug)
      Apartment::Tenant.drop(org.slug)
      attachment_ids
    end

    # Collect the public attachment ids backing the tenant's records while the
    # schema (and its rows) still exist — after the DROP we can no longer
    # enumerate the tenant Media/LabelPrintRun to find them. `unscoped` reaches
    # soft-deleted rows too (Media's `default_scope { kept }` would otherwise hide
    # discarded photos and orphan their blobs/files). Best-effort: a failure here
    # only risks orphaned storage, never a routable schema, so it must not abort
    # the drop. Accumulate into a local rather than the block's value, since the
    # attachment rows live in the public schema regardless of the active tenant.

    #: (untyped slug) -> Array[untyped]
    def capture_attachment_ids(slug)
      ids = []
      # A savepoint: a failing query here must not abort the enclosing teardown
      # transaction (Postgres refuses every later statement in an aborted one).
      ActiveRecord::Base.transaction(requires_new: true) do
        capture_into(ids, slug)
      end
      ids
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- best-effort capture must not abort the drop
      Rails.logger.error("[accounts.delete] attachment capture failed for #{slug}: #{e.class}: #{e.message}")
      # A failed switch-back inside the aborted savepoint can leave Apartment's
      # notion of the current tenant on the slug we are about to drop.
      Apartment::Tenant.reset
      ids || [] # the rescue can technically fire before `ids = []` assigns
    end

    #: (Array[untyped] ids, untyped slug) -> void
    def capture_into(ids, slug)
      Apartment::Tenant.switch(slug) do
        TENANT_ATTACHMENTS.each_key do |model|
          record_ids = model.unscoped.pluck(:id)
          next if record_ids.empty?

          ids.concat(
            ActiveStorage::Attachment.where(record_type: model.name, record_id: record_ids).pluck(:id)
          )
        end
      end
    end

    # Purges the captured attachments (detaching the public row and enqueuing the
    # blob + variants + stored-file deletion) now that the tenant schema is gone.
    # Best-effort: a failure only orphans storage and must not fail an
    # already-dropped tenant.

    #: (untyped attachment_ids) -> void
    def purge_attachments(attachment_ids)
      ActiveStorage::Attachment.where(id: attachment_ids).find_each(&:purge_later)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- best-effort purge must not fail an already-dropped tenant
      Rails.logger.error("[accounts.delete] attachment purge failed: #{e.class}: #{e.message}")
    end

    #: (untyped user) -> Dry::Monads::Result[untyped, untyped]
    def delete_user(user)
      # Handoff tokens (public, #280) reference user_id with no FK, so user.destroy!
      # won't cascade them — delete them explicitly so nothing user-owned lingers.
      # (They are digest-only + single-use + auto-purged, so this is completeness,
      # not a security fix.)
      SessionHandoffToken.where(user_id: user.id).delete_all
      user.destroy! # auth tables cascade; org memberships already gone with their orgs
      Success()
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      Failure(e.message)
    end

    #: (untyped snapshot) -> Dry::Monads::Success[nil]
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
