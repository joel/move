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
      move: @move,
      memberships: @move.move_memberships.includes(:user).order(:role, :created_at),
      candidates: candidate_users,
      current_user_id: current_user.id
    )
  end

  # POST /moves/:move_id/members
  def create
    result = MoveMemberships::Add.new.call(
      move: @move, user_id: member_param(:user_id), role: member_param(:role), actor: current_user
    )

    case result
    in Dry::Monads::Success(_membership)
      redirect_to move_members_path(@move), notice: t(".added")
    in Dry::Monads::Failure(_)
      # Cross-org / unknown user (:not_found), bad role (:invalid_role), or a
      # uniqueness error all resolve to the same non-disclosing message.
      redirect_to move_members_path(@move), alert: t(".add_failed")
    end
  end

  # PATCH /moves/:move_id/members/:id/update_role
  def update_role
    result = MoveMemberships::ChangeRole.new.call(
      membership: membership, role: member_param(:role), actor: current_user
    )

    case result
    in Dry::Monads::Success(_membership)
      redirect_to move_members_path(@move), notice: t(".role_changed")
    in Dry::Monads::Failure(:last_admin)
      redirect_to move_members_path(@move), alert: t(".last_admin")
    in Dry::Monads::Failure(_)
      redirect_to move_members_path(@move), alert: t(".role_change_failed")
    end
  end

  # DELETE /moves/:move_id/members/:id
  def destroy
    result = MoveMemberships::Remove.new.call(membership: membership, actor: current_user)

    case result
    in Dry::Monads::Success(_details)
      redirect_to move_members_path(@move), notice: t(".removed")
    in Dry::Monads::Failure(:last_admin)
      redirect_to move_members_path(@move), alert: t(".last_admin")
    in Dry::Monads::Failure(_)
      redirect_to move_members_path(@move), alert: t(".remove_failed")
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

  # Organization users not already on this Move — the only valid candidates,
  # since a Move cannot be shared outside its Organization.
  def candidate_users
    organization = Organization.find_by(slug: Apartment::Tenant.current)
    return User.none if organization.nil?

    organization.users
                .where.not(id: @move.move_memberships.select(:user_id))
                .order(:email)
  end
end
