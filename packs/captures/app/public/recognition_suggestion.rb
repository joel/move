# frozen_string_literal: true

# A normalized proposed item from a recognition run (Domain §4.11). Carries no
# bounding boxes or vendor data — just a proposed name + confidence. May
# materialize into an Item (auto-accepted at/above the Move threshold, else
# pending).
class RecognitionSuggestion < ApplicationRecord
  STATES = %w[pending auto_accepted accepted corrected needs_correction false_positive conflict].freeze

  belongs_to :move
  belongs_to :box
  belongs_to :media
  belongs_to :recognition_run
  belongs_to :item, optional: true

  validates :proposed_name, presence: true
  validates :state, inclusion: { in: STATES }

  # Still needs a human decision in the review queue (D6): a fresh low-confidence
  # suggestion, or one that conflicts with an already-confirmed item.
  UNRESOLVED = %w[pending conflict].freeze

  scope :unresolved, -> { where(state: UNRESOLVED) }
  # Review item-by-item walks lowest-confidence first; NULLs (no score) last.
  scope :by_confidence, -> { order(Arel.sql("confidence_score ASC NULLS LAST")) }

  #: () -> bool
  def unresolved?
    UNRESOLVED.include?(state)
  end

  #: () -> bool
  def conflict?
    state == "conflict"
  end

  #: () -> untyped
  def confidence_percent
    # Bind once: two separate attribute reads defeat nil-narrowing (Steep is
    # right — a method call isn't a stable local), and one read is better anyway.
    score = confidence_score
    return nil if score.nil?

    (score * 100).round
  end
end
