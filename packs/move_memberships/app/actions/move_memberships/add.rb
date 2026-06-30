# frozen_string_literal: true

# pack_public: true -- public API of packs/move_memberships: adds a member (MembersController).
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module MoveMemberships
  # Adds an existing Organization user to a Move with a role (F1, D11).
  #
  # A Move can only be shared with members of its Organization, so the candidate
  # must already hold an OrganizationMembership for the current tenant. A user_id
  # that is not an Org member is rejected non-disclosingly (:not_found) — the
  # same response as an unknown id, so admins cannot probe Org membership.
  #
  # MoveMembership lives in the tenant schema; Organization/OrganizationMembership
  # are excluded_models (public schema), so they resolve on the public connection
  # even while Apartment has switched to the tenant.
  class Add < BaseAction
    def call(move:, user_id:, role:, actor:)
      yield ensure_known_role(role)
      organization = yield current_organization
      user = yield organization_member(organization, user_id)
      membership = yield persist(move, user, role)
      yield emit_event(move, membership, actor)
      Success(membership)
    end

    private

    def ensure_known_role(role)
      return Failure(:invalid_role) unless MoveMembership::ROLES.include?(role.to_s)

      Success()
    end

    def current_organization
      organization = Organization.find_by(slug: Apartment::Tenant.current)
      return Failure(:not_found) if organization.nil?

      Success(organization)
    end

    # The candidate must be a member of this Organization. Non-disclosing on miss.
    def organization_member(organization, user_id)
      member = organization.users.find_by(id: user_id)
      return Failure(:not_found) if member.nil?

      Success(member)
    end

    def persist(move, user, role)
      Success(move.move_memberships.create!(user: user, role: role.to_s))
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    rescue ActiveRecord::RecordNotUnique
      # A concurrent duplicate (double-submit / two admins) can race past the
      # uniqueness validation and hit the (move_id, user_id) unique index. Treat
      # it as the same non-disclosing failure as a sequential duplicate, never a
      # 500.
      Failure(:already_member)
    end

    def emit_event(move, membership, actor)
      Rails.event.notify(
        "move_membership.added",
        move_id: move.id,
        user_id: membership.user_id,
        role: membership.role,
        actor_id: actor&.id
      )
      Success()
    end
  end
end
