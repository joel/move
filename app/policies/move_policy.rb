# frozen_string_literal: true

# Moves are already isolated by the Apartment tenant schema, so the relation
# scope is the tenant's full set. Membership-level rules live here for the
# mutating actions added in later phases.
class MovePolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def create?
    user.present?
  end

  relation_scope do |relation|
    next relation.none if user.blank?

    relation
  end
end
