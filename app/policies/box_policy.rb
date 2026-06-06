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

  def create?
    user.present? && record.move&.writable?
  end

  relation_scope do |relation|
    next relation.none if user.blank?

    relation
  end
end
