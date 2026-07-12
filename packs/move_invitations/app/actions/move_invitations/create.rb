# frozen_string_literal: true

# pack_public: true -- public API of packs/move_invitations: mints an email invitation (InvitationsController).
# Kept in its layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module MoveInvitations
  # Invite any email address to a Move with a role (Phase D14, #608). Persists a
  # pending MoveInvitation carrying only the token digest; the raw token travels
  # once, in the invitation email. Runs in tenant context (the Members screen),
  # so the current Apartment tenant names the Organization the invite belongs to.
  #
  # An email that already belongs to a member of THIS Move is rejected as
  # :already_member — the admin can already see the roster's emails, so this
  # discloses nothing new. Whether the address has a User account elsewhere is
  # never revealed.
  class Create < BaseAction
    #: (move: untyped, email: untyped, role: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, email:, role:, actor:)
      normalized = email.to_s.strip
      yield ensure_email(normalized)
      yield ensure_known_role(role)
      organization = yield current_organization
      yield ensure_not_move_member(move, normalized)
      raw = MoveInvitation.generate_raw_token
      invitation = yield persist(
        organization: organization, move_id: move.id, email: normalized, role: role.to_s,
        invited_by_id: actor&.id, token_digest: MoveInvitation.digest(raw),
        expires_at: MoveInvitation::TTL.from_now
      )
      yield emit_event(invitation, actor)
      deliver(invitation, raw)
      Success(invitation)
    end

    private

    #: (untyped email) -> Dry::Monads::Result[untyped, untyped]
    def ensure_email(email)
      return Failure(:invalid_email) unless email.match?(URI::MailTo::EMAIL_REGEXP)

      Success()
    end

    #: (untyped role) -> Dry::Monads::Result[untyped, untyped]
    def ensure_known_role(role)
      return Failure(:invalid_role) unless MoveMembership::ROLES.include?(role.to_s)

      Success()
    end

    #: () -> Dry::Monads::Result[untyped, untyped]
    def current_organization
      organization = Organization.find_by(slug: Apartment::Tenant.current)
      return Failure(:not_found) if organization.nil?

      Success(organization)
    end

    # citext on users.email makes this lookup case-insensitive, matching the
    # accept-time binding.

    #: (untyped move, untyped email) -> Dry::Monads::Result[untyped, untyped]
    def ensure_not_move_member(move, email)
      user_id = User.where(email: email).pick(:id)
      return Success() if user_id.nil?
      return Failure(:already_member) if move.move_memberships.exists?(user_id: user_id)

      Success()
    end

    #: (**untyped attrs) -> Dry::Monads::Result[untyped, untyped]
    def persist(**attrs)
      Success(MoveInvitation.create!(**attrs))
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    rescue ActiveRecord::RecordNotUnique
      # The pending partial unique index: one live invitation per (move, email).
      # A concurrent double-submit lands here instead of a 500; the UI points at
      # Resend.
      Failure(:already_invited)
    end

    #: (untyped invitation, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(invitation, actor)
      Rails.event.notify(
        "move_invitation.created",
        move_id: invitation.move_id,
        invitation_id: invitation.id,
        email: invitation.email,
        role: invitation.role,
        actor_id: actor&.id
      )
      Success()
    end

    # The invite email carries the raw token (its only home). The row is already
    # committed (no surrounding transaction on this path), so enqueueing here
    # cannot race a rollback; delivery failures surface in the mailer job, never
    # fail the invite itself.

    #: (untyped invitation, untyped raw) -> void
    def deliver(invitation, raw)
      MoveInvitationMailer.invite(invitation_id: invitation.id, raw_token: raw).deliver_later
    end
  end
end
