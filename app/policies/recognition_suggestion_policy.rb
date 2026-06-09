# frozen_string_literal: true

# Recognition suggestions are isolated by the Apartment tenant schema and scoped
# to a Move/Box in the controller (a non-member 404s at the Move). Any member can
# view the review queue; resolving a suggestion (keep/correct/false-positive)
# requires the admin/contributor (editor) tier and a writable (non-archived)
# Move — so viewers, and any member on an archived Move, cannot mutate.
class RecognitionSuggestionPolicy < ApplicationPolicy
  include MoveMembershipAuthorization

  def index?
    reader_of?(record_move)
  end

  def show?
    reader_of?(record_move)
  end

  def keep?
    editor_of?(record_move)
  end

  alias correct? keep?
  alias mark_false_positive? keep?

  relation_scope do |relation|
    next relation.none if user.blank?

    relation
  end

  private

  def record_move
    record.is_a?(Move) ? record : record&.move
  end
end
