# frozen_string_literal: true

# pack_public: true -- public API of packs/move_invitations: accepts an invitation (InvitationAcceptancesController).
# Kept in its layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module MoveInvitations
  # Accept an invitation (Phase D14, #608). Runs on the APEX (no tenant active)
  # with an authenticated user; acceptance is BOUND to the invited email — the
  # link is a claim check, authenticating as that mailbox is the credential.
  #
  # Order is load-bearing (Design Spec F1): validate everything — including that
  # the Move still exists (tenant switch) — BEFORE any join, so a dead Move never
  # creates an org membership; then atomically claim; then the idempotent
  # org-join; then the idempotent move-join inside the tenant. A re-click of an
  # already-accepted invitation by the matching user re-runs the joins and
  # succeeds, which makes a crash between claim and joins self-healing and a
  # double-accept (two tabs) a non-event. The org membership is never rolled
  # back on a later failure — it is the durable prerequisite.
  #
  # Every failure collapses to an opaque reason; the controller renders ONE
  # generic "unavailable" page for all of them (non-disclosing).
  class Accept < BaseAction
    #: (raw_token: untyped, user: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(raw_token:, user:)
      invitation = yield find(raw_token)
      yield ensure_email_match(invitation, user)
      organization = invitation.organization
      yield ensure_move_writable(organization, invitation)
      yield claim_or_resume(invitation)
      yield join_organization(organization, user)
      yield join_move_and_record(organization, invitation, user)
      Success({ organization: organization, move_id: invitation.move_id })
    end

    private

    #: (untyped raw_token) -> Dry::Monads::Result[untyped, untyped]
    def find(raw_token)
      return Failure(:invalid) if raw_token.blank?

      invitation = MoveInvitation.find_by(token_digest: MoveInvitation.digest(raw_token))
      invitation ? Success(invitation) : Failure(:invalid)
    end

    # citext: the column comparison is case-insensitive; mirror it here.

    #: (untyped invitation, untyped user) -> Dry::Monads::Result[untyped, untyped]
    def ensure_email_match(invitation, user)
      return Failure(:mismatch) unless invitation.email.to_s.casecmp?(user.email.to_s)

      Success()
    end

    # Validate the Move BEFORE any join (so a dead/archived Move never creates
    # an org membership). Archived is folded in with gone: an archived Move is
    # read-only (AGENTS.md §2 "archived-Move guard" — a mutating action must not
    # write to it), and adding a member is a mutation. The invitation stays
    # unclaimed, so the link revives if the Move is un-archived; both collapse
    # to the one generic unavailable page.

    #: (untyped organization, untyped invitation) -> Dry::Monads::Result[untyped, untyped]
    def ensure_move_writable(organization, invitation)
      writable = Apartment::Tenant.switch(organization.slug) do
        Move.find_by(id: invitation.move_id)&.writable?
      end
      writable ? Success() : Failure(:gone)
    rescue Apartment::TenantNotFound
      Failure(:gone)
    end

    # Atomic single-use claim (SessionHandoffs::Consume pattern), with a resume
    # path: an invitation this user already accepted re-runs the idempotent
    # joins instead of failing — two tabs, a crash between claim and joins, or a
    # lost redirect all recover by re-clicking the link.

    #: (untyped invitation) -> Dry::Monads::Result[untyped, untyped]
    def claim_or_resume(invitation)
      return Success(:resumed) if invitation.accepted?
      return Failure(:revoked) if invitation.revoked?
      return Failure(:expired) if invitation.expired?

      # rubocop:disable Rails/SkipsModelValidations -- atomic single-use claim:
      # exactly one caller flips accepted_at; the WHERE also backstops a revoke
      # or expiry racing past the pre-checks above.
      claimed = MoveInvitation
                .where(id: invitation.id, accepted_at: nil, revoked_at: nil)
                .where(expires_at: Time.current..)
                .update_all(accepted_at: Time.current)
      # rubocop:enable Rails/SkipsModelValidations
      return Success(:claimed) if claimed == 1

      # Lost the race — to our own other tab (resume) or to a revoke (fail).
      invitation.reload.accepted? ? Success(:resumed) : Failure(:revoked)
    end

    # Idempotent org-join with the base role. find_or_create_by! + the unique
    # rescue covers both the sequential and the concurrent duplicate; the model's
    # own uniqueness validation raises RecordInvalid on the sequential path.

    #: (untyped organization, untyped user) -> Dry::Monads::Result[untyped, untyped]
    def join_organization(organization, user)
      OrganizationMembership.find_or_create_by!(organization: organization, user: user) do |m|
        m.role = "member"
      end
      Success()
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # A concurrent join (second tab) landed first; membership now exists.
      membership = OrganizationMembership.exists?(organization: organization, user: user)
      membership ? Success() : Failure(:invalid)
    end

    # The move-join and both tenant-side records (the membership event from Add,
    # our accepted event) happen inside the tenant switch: the activity
    # subscriber writes to Apartment::Tenant.current, and these rows belong to
    # the Move's schema.

    #: (untyped organization, untyped invitation, untyped user) -> Dry::Monads::Result[untyped, untyped]
    def join_move_and_record(organization, invitation, user)
      Apartment::Tenant.switch(organization.slug) do
        move = Move.find_by(id: invitation.move_id)
        next Failure(:gone) if move.nil?

        joined = join_move(move, invitation, user)
        next joined if joined.failure?

        emit_accepted(invitation, user)
        Success()
      end
    rescue Apartment::TenantNotFound
      Failure(:gone)
    end

    # Idempotent: an existing membership is success (the resume path re-runs the
    # join). The pre-check catches the sequential duplicate — MoveMembership's
    # uniqueness VALIDATION fires before the index, so Add would return
    # Failure(errors), not :already_member — and Add's RecordNotUnique rescue
    # still covers the concurrent one.

    #: (untyped move, untyped invitation, untyped user) -> Dry::Monads::Result[untyped, untyped]
    def join_move(move, invitation, user)
      return Success() if move.move_memberships.exists?(user_id: user.id)

      result = MoveMemberships::Add.new.call(
        move: move, user_id: user.id, role: invitation.role, actor: user
      )
      return Success() if result.success? || result.failure == :already_member

      Failure(:invalid)
    end

    #: (untyped invitation, untyped user) -> void
    def emit_accepted(invitation, user)
      Rails.event.notify(
        "move_invitation.accepted",
        move_id: invitation.move_id,
        invitation_id: invitation.id,
        email: invitation.email,
        actor_id: user.id
      )
    end
  end
end
