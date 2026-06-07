# frozen_string_literal: true

# Authorizes management of a Move's controlled vocabularies (categories, tags,
# rooms — D7). The authorized record is the **Move**: viewing the management
# surface is open to any signed-in member, but adding / renaming / removing a
# value is admin-only and only on a writable (non-archived) Move. Roles are
# admin/member today; contributor/viewer arrive in D11.
class VocabularyPolicy < ApplicationPolicy
  # record is the Move whose vocabularies are managed. Viewing requires
  # membership — a signed-in user from another Move in the same tenant must not
  # see this Move's category/tag/room names.
  def index?
    member?
  end

  def manage?
    member?(role: "admin") && record.writable?
  end

  alias create? manage?
  alias update? manage?
  alias destroy? manage?

  private

  # Whether the user belongs to this Move (optionally with a specific role).
  # Authorization stays in the policy (not the Move model) per AGENTS.md §2 — the
  # contributor/viewer split (D11) refines it here. Roles are admin/member today.
  def member?(role: nil)
    return false if user.nil?

    scope = record.move_memberships.where(user_id: user.id)
    scope = scope.where(role: role) if role
    scope.exists?
  end
end
