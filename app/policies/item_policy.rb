# frozen_string_literal: true

# Items are isolated by the Apartment tenant schema and scoped to a Move/Box in
# the controller (a non-member 404s at the Move). Any member may read; mutating
# an Item (D5 create/edit/move/remove/restore) requires the admin/contributor
# (editor) tier and a writable (non-archived) Move — so a viewer, or any member
# on an archived Move, cannot mutate.
class ItemPolicy < ApplicationPolicy
  include MoveMembershipAuthorization

  def index?
    reader_of?(record_move)
  end

  def show?
    reader_of?(record_move)
  end

  def create?
    editor_of?(record_move)
  end

  alias update? create?
  alias move? create?
  alias mark_removed? create?
  alias restore? create?

  relation_scope do |relation|
    next relation.none if user.blank?

    relation
  end

  private

  def record_move
    record.is_a?(Move) ? record : record&.move
  end
end
