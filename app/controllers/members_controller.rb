# frozen_string_literal: true

# F1 — Members & roles. Admin-only management of who can access a Move and what
# they can do. Adds an existing Organization user, changes a member's role, or
# removes them. A Move can only be shared with members of its Organization, so
# candidates are drawn from the current tenant's Organization users. Thin:
# authorize (manage_members?), call the action, pattern-match, redirect.
class MembersController < MoveScopedController
  before_action :require_member_admin!

  # GET /moves/:move_id/members
  def index
    render Views::Members::Index.new(
      move: @move, memberships: memberships, candidates: candidates, current_user_id: current_user.id
    )
  end

  # POST /moves/:move_id/members — streams the new member into the (re-sorted,
  # highlighted) roster and refreshes the add form (the added user leaves the
  # candidate pool); a toast confirms. A failed add just toasts the reason.
  def create
    result = MoveMemberships::Add.new.call(
      move: @move, user_id: member_param(:user_id), role: member_param(:role), actor: current_user
    )

    case result
    in Dry::Monads::Success(membership)
      respond_with_streams([list_stream(highlight_id: membership.id), *candidate_pool_streams],
                           redirect: index_path, toast: true) { [:notice, t(".added")] }
    in Dry::Monads::Failure(_)
      # Cross-org / unknown user (:not_found), bad role (:invalid_role), or a
      # uniqueness error all resolve to the same non-disclosing message.
      respond_with_streams([], redirect: index_path, toast: true, status: :unprocessable_content) do
        [:alert, t(".add_failed")]
      end
    end
  end

  # PATCH /moves/:move_id/members/:id/update_role — the role select auto-submits.
  # Success re-renders the roster (re-sorted by role, the changed member
  # highlighted); a last-admin/failed change re-streams just that row so its
  # select reverts to the persisted role, plus an alert toast.
  def update_role
    result = MoveMemberships::ChangeRole.new.call(
      membership: membership, role: member_param(:role), actor: current_user
    )

    case result
    in Dry::Monads::Success(updated)
      respond_with_streams([list_stream(highlight_id: updated.id)],
                           redirect: index_path, toast: true) { [:notice, t(".role_changed")] }
    in Dry::Monads::Failure(reason)
      key = reason == :last_admin ? ".last_admin" : ".role_change_failed"
      respond_with_streams([row_stream(membership.reload)], redirect: index_path,
                                                            toast: true, status: :unprocessable_content) { [:alert, t(key)] }
    end
  end

  # DELETE /moves/:move_id/members/:id — streams the row out and refreshes the add
  # form (the removed user rejoins the candidate pool); a toast confirms.
  def destroy
    target = membership
    result = MoveMemberships::Remove.new.call(membership: target, actor: current_user)

    case result
    in Dry::Monads::Success(_details)
      respond_with_streams([turbo_stream.remove(Components::Members::Row.dom_id(target)), *candidate_pool_streams],
                           redirect: index_path, toast: true) { [:notice, t(".removed")] }
    in Dry::Monads::Failure(reason)
      key = reason == :last_admin ? ".last_admin" : ".remove_failed"
      respond_with_streams([], redirect: index_path, toast: true, status: :unprocessable_content) do
        [:alert, t(key)]
      end
    end
  end

  private

  def require_member_admin!
    authorize! @move, to: :manage_members?, with: MovePolicy
  end

  def membership
    @membership ||= @move.move_memberships.find(params.expect(:id))
  end

  # Read a single member[...] field. These scalars are not mass-assigned to a
  # model — they are passed as explicit arguments to the MoveMemberships actions,
  # which validate the role (against MoveMembership::ROLES) and the user (must be
  # an Organization member) — so no strong-params permit is needed here.
  def member_param(key)
    params.dig(:member, key)
  end

  def index_path
    move_members_path(@move)
  end

  def memberships
    @move.move_memberships.includes(:user).order(:role, :created_at)
  end

  # Organization users not already on this Move — the only valid candidates,
  # since a Move cannot be shared outside its Organization.
  def candidates
    organization = Organization.find_by(slug: Apartment::Tenant.current)
    return User.none if organization.nil?

    organization.users
                .where.not(id: @move.move_memberships.select(:user_id))
                .order(:email)
  end

  # Replace the whole stable roster — the added/changed member lands at its
  # role-sorted position, highlighted. Always replace this guaranteed-present
  # wrapper rather than appending to it.
  def list_stream(highlight_id: nil)
    turbo_stream.replace(
      Components::Members::List::ID,
      view_context.render(Components::Members::List.new(
                            move: @move, memberships: memberships,
                            current_user_id: current_user.id, highlight_id: highlight_id
                          ))
    )
  end

  def row_stream(membership)
    turbo_stream.replace(
      Components::Members::Row.dom_id(membership),
      view_context.render(Components::Members::Row.new(
                            move: @move, membership: membership, current_user_id: current_user.id
                          ))
    )
  end

  # Everything that tracks the candidate pool, refreshed together when it changes
  # (a member added leaves it; a member removed rejoins it): the add-member form
  # AND the header Invite CTA both hide when none remain / reappear when one does.
  def candidate_pool_streams
    pool = candidates
    [
      turbo_stream.replace(Components::Members::AddForm::ID,
                           view_context.render(Components::Members::AddForm.new(move: @move, candidates: pool))),
      turbo_stream.replace(Components::Members::Header::ID,
                           view_context.render(Components::Members::Header.new(move: @move, candidates: pool)))
    ]
  end
end
