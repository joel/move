# frozen_string_literal: true

# Moves are isolated by the Apartment tenant schema, and from D11 further scoped
# to the user's MoveMemberships: the relation scope returns only Moves the user
# belongs to, so a signed-in user from another Move in the same Organization
# cannot load it. Role-level rules (read/edit/admin) live in
# MoveMembershipAuthorization.
class MovePolicy < ApplicationPolicy
  include MoveMembershipAuthorization

  def index?
    user.present?
  end

  def show?
    reader_of?(record)
  end

  # Creating a Move requires membership of the current Organization, not merely a
  # session — otherwise a session that reached a foreign subdomain could create a
  # Move and self-assign admin. The tenant boundary (TenantController#require_membership!)
  # already enforces this; this keeps the policy itself honest (defense in depth).
  # Apartment::Tenant.current is the active tenant slug, mirroring how the domain
  # actions resolve the current Organization.
  def create?
    return false if user.nil?

    Organization.member?(user_id: user.id, slug: Apartment::Tenant.current)
  end

  # Holds an editing role (admin/contributor) on the Move. The controller pairs
  # this with the archived (read-only) redirect, so a viewer gets a 403 while an
  # editor on an archived Move gets the friendly read-only redirect instead.
  def edit_contents?
    editor_role?(record)
  end

  # F1 — managing members and their roles is admin-only.
  def manage_members?
    admin_of?(record)
  end

  # F3 — changing Move-level settings (unit system, auto-confirm threshold) needs
  # an editing role, consistent with the F2 unit-system toggle. The controller
  # pairs this with the archived read-only guard.
  def edit_settings?
    editor_role?(record)
  end

  # Deleting a Move outright (today only the onboarding sample, #432) is admin-only
  # — it is irreversible and removes every box, item and photo.
  def destroy?
    admin_of?(record)
  end

  # F3 — creating/revoking MCP integration tokens is admin-only (Domain §4.13).
  def manage_integration_tokens?
    admin_of?(record)
  end

  # Recognition provider API keys are secrets, so managing them is admin-only
  # (#185), mirroring integration tokens. Viewers/contributors see the active
  # provider read-only.
  def manage_recognition_keys?
    admin_of?(record)
  end

  relation_scope do |relation|
    next relation.none if user.blank?

    relation.where(id: MoveMembership.where(user_id: user.id).select(:move_id))
  end
end
