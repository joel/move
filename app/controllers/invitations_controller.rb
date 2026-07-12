# frozen_string_literal: true

# D14 (#608) — email invitations to a Move (admin-only, tenant side). Invite any
# address with a role, re-send (rotating the link), or revoke. Pending
# invitations render on the Members page (F1); acceptance happens on the apex
# (InvitationAcceptancesController). Thin: authorize, call the action,
# pattern-match, stream.
class InvitationsController < MoveScopedController
  before_action :require_member_admin!

  # Bounds invitation email volume per admin.
  # steep: the Rails 8 rate_limit macro predates the 7.0-era actionpack sigs,
  # so the generated interface lacks it.
  rate_limit to: 10, within: 1.hour, by: -> { current_user&.id }, only: %i[create resend], with: -> { head :too_many_requests } # steep:ignore NoMethod

  # POST /moves/:move_id/invitations — streams the new invitation to the top of
  # the pending list (highlighted; UX rule #1) and toasts; the invite form
  # clears + refocuses client-side (reset-form). Failures keep the input and
  # name the remedy.

  #: () -> untyped
  def create
    result = MoveInvitations::Create.new.call(
      move: @move, email: invitation_param(:email), role: invitation_param(:role), actor: current_user
    )

    case result
    in Dry::Monads::Success(invitation)
      respond_with_streams([pending_stream(highlight_id: invitation.id)],
                           redirect: index_path, toast: true) { [:notice, t(".sent", email: invitation.email)] }
    in Dry::Monads::Failure(reason)
      respond_with_streams([], redirect: index_path, toast: true, status: :unprocessable_content) do
        [:alert, create_failure_message(reason)]
      end
    end
  end

  # POST /moves/:move_id/invitations/:id/resend — rotates the link (the old one
  # dies instantly) and re-mails; the row re-renders in place with the fresh
  # expiry. Works on expired-but-pending rows (revive).

  #: () -> untyped
  def resend
    result = MoveInvitations::Resend.new.call(invitation: invitation, actor: current_user)

    case result
    in Dry::Monads::Success(rotated)
      respond_with_streams([row_stream(rotated)],
                           redirect: index_path, toast: true) { [:notice, t(".resent", email: rotated.email)] }
    in Dry::Monads::Failure(_reason)
      # Accepted or revoked since the page rendered — refresh the whole list so
      # the stale row disappears.
      respond_with_streams([pending_stream], redirect: index_path,
                                             toast: true, status: :unprocessable_content) { [:alert, t(".resend_failed")] }
    end
  end

  # DELETE /moves/:move_id/invitations/:id — revokes (the emailed link dies) and
  # streams the row out.

  #: () -> untyped
  def destroy
    target = invitation
    result = MoveInvitations::Revoke.new.call(invitation: target, actor: current_user)

    case result
    in Dry::Monads::Success(_revoked)
      respond_with_streams([turbo_stream.remove(Components::Members::PendingRow.dom_id(target))],
                           redirect: index_path, toast: true) { [:notice, t(".revoked", email: target.email)] }
    in Dry::Monads::Failure(_reason)
      respond_with_streams([pending_stream], redirect: index_path,
                                             toast: true, status: :unprocessable_content) { [:alert, t(".revoke_failed")] }
    end
  end

  private

  #: () -> void
  def require_member_admin!
    authorize! @move, to: :manage_members?, with: MovePolicy
  end

  # Scoped to THIS move — a stray id from another Move's invitation 404s.

  #: () -> untyped
  def invitation
    @invitation ||= MoveInvitation.where(move_id: @move.id).find(params.expect(:id))
  end

  # Scalars passed as explicit action arguments (which validate email shape and
  # role) — not mass-assigned, so no strong-params permit is needed.

  #: (Symbol key) -> untyped
  def invitation_param(key)
    params.dig(:invitation, key)
  end

  #: (untyped reason) -> String
  def create_failure_message(reason)
    case reason
    when :already_invited then t(".already_invited", email: invitation_param(:email).to_s.strip)
    when :already_member then t(".already_member")
    when :invalid_email then t(".invalid_email")
    else t(".failed")
    end
  end

  #: () -> String
  def index_path
    move_members_path(@move)
  end

  #: () -> untyped
  def pending_invitations
    MoveInvitation.pending.where(move_id: @move.id).order(created_at: :desc)
  end

  # Replace the whole stable pending-list container — a new invitation lands at
  # the top (recency), highlighted; an emptied list collapses to nothing.

  #: (?highlight_id: untyped) -> untyped
  def pending_stream(highlight_id: nil)
    turbo_stream.replace(
      Components::Members::PendingInvitations::ID,
      view_context.render(Components::Members::PendingInvitations.new(
                            move: @move, invitations: pending_invitations, highlight_id: highlight_id
                          ))
    )
  end

  #: (untyped record) -> untyped
  def row_stream(record)
    turbo_stream.replace(
      Components::Members::PendingRow.dom_id(record),
      view_context.render(Components::Members::PendingRow.new(move: @move, invitation: record))
    )
  end
end
