# frozen_string_literal: true

# Items are isolated by the Apartment tenant schema and scoped to a Move/Box in
# the controller. Read access for any signed-in member; mutating an Item (D5
# create/edit/move/remove/restore) additionally requires a writable
# (non-archived) Move — so a viewer on an archived Move cannot mutate. Per-role
# viewer/contributor rules arrive in D11.
class ItemPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def create?
    user.present? && record.move&.writable?
  end

  alias update? create?
  alias move? create?
  alias mark_removed? create?
  alias restore? create?

  relation_scope do |relation|
    next relation.none if user.blank?

    relation
  end
end
