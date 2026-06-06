# frozen_string_literal: true

# Items are isolated by the Apartment tenant schema and scoped to a Move/Box in
# the controller. Read access for any signed-in member; edit/review land in D5/D6.
class ItemPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  relation_scope do |relation|
    next relation.none if user.blank?

    relation
  end
end
