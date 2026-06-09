# frozen_string_literal: true

# Boxes are isolated by the Apartment tenant schema and scoped to a Move in the
# controller, so a non-member never reaches them (MovePolicy.relation_scope 404s
# the Move first). Reading a Box — including the opaque exterior label and the
# sensitive manifest (#86) — requires move membership; mutating one requires the
# admin/contributor (editor) tier and a writable (non-archived) Move.
class BoxPolicy < ApplicationPolicy
  include MoveMembershipAuthorization

  def index?
    reader_of?(record_move)
  end

  def show?
    reader_of?(record_move)
  end

  # E1 — the exterior label and the (sensitive) contents manifest are readable by
  # any member who can view the box (viewer included), and by no one else (#86).
  alias label? show?
  alias manifest? show?

  def create?
    editor_of?(record_move)
  end

  alias edit? create?
  alias update? create?
  alias transition? create?

  relation_scope do |relation|
    next relation.none if user.blank?

    relation
  end

  private

  # The Move governing this record — the Box's Move, or the record itself when a
  # Move is authorized directly.
  def record_move
    record.is_a?(Move) ? record : record&.move
  end
end
