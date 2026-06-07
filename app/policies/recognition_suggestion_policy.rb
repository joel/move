# frozen_string_literal: true

# Recognition suggestions are isolated by the Apartment tenant schema and scoped
# to a Move/Box in the controller. Any signed-in member can view the review
# queue; resolving a suggestion (keep/correct/false-positive) requires a writable
# (non-archived) Move — so viewers/archived Moves cannot mutate. Per-role rules
# arrive in D11.
class RecognitionSuggestionPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def keep?
    user.present? && record.move&.writable?
  end

  alias correct? keep?
  alias mark_false_positive? keep?

  relation_scope do |relation|
    next relation.none if user.blank?

    relation
  end
end
