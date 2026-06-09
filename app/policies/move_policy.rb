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

  def create?
    user.present?
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

  # F3 — creating/revoking MCP integration tokens is admin-only (Domain §4.13).
  def manage_integration_tokens?
    admin_of?(record)
  end

  relation_scope do |relation|
    next relation.none if user.blank?

    relation.where(id: MoveMembership.where(user_id: user.id).select(:move_id))
  end
end
