# frozen_string_literal: true

# Boxes are isolated by the Apartment tenant schema and further scoped to a
# Move in the controller, so the relation scope is the tenant's full set for a
# signed-in user. Mutating a Box additionally requires a writable (non-archived)
# Move — enforced in the controller; viewer/contributor role rules arrive in D11.
class BoxPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  # E1 — printing the opaque exterior label and the (sensitive) manifest is
  # available to anyone who can view the box. Read access matches show? for now;
  # the member/role refinement arrives with D11 (see MovePolicy).
  alias label? show?
  alias manifest? show?

  def create?
    user.present? && record.move&.writable?
  end

  alias edit? create?
  alias update? create?
  alias transition? create?

  relation_scope do |relation|
    next relation.none if user.blank?

    relation
  end
end
