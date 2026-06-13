# frozen_string_literal: true

# A normalized proposed item from a recognition run (Domain §4.11). Carries no
# bounding boxes or vendor data. May materialize into an Item (auto-accepted
# at/above the Move threshold, else pending). The model also proposes a category
# (best-effort onto the Move vocabulary) and a fragility flag.
class RecognitionSuggestion < ApplicationRecord
  STATES = %w[pending auto_accepted accepted corrected needs_correction false_positive conflict].freeze

  belongs_to :move
  belongs_to :box
  belongs_to :media
  belongs_to :recognition_run
  belongs_to :item, optional: true
  belongs_to :proposed_category, class_name: "Category", optional: true

  validates :proposed_name, presence: true
  validates :proposed_quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :state, inclusion: { in: STATES }

  # Still needs a human decision in the review queue (D6): a fresh low-confidence
  # suggestion, or one that conflicts with an already-confirmed item.
  UNRESOLVED = %w[pending conflict].freeze

  scope :unresolved, -> { where(state: UNRESOLVED) }
  # Review item-by-item walks lowest-confidence first; NULLs (no score) last.
  scope :by_confidence, -> { order(Arel.sql("confidence_score ASC NULLS LAST")) }

  def unresolved?
    UNRESOLVED.include?(state)
  end

  def conflict?
    state == "conflict"
  end

  def confidence_percent
    return nil if confidence_score.nil?

    (confidence_score * 100).round
  end
end
