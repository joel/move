# frozen_string_literal: true

# A normalized proposed item from a recognition run (Domain §4.11). Carries no
# bounding boxes or vendor data. Category/tags are deferred to D7. May materialize
# into an Item (auto-accepted at/above the Move threshold, else pending).
class RecognitionSuggestion < ApplicationRecord
  STATES = %w[pending auto_accepted accepted corrected needs_correction false_positive conflict].freeze

  belongs_to :move
  belongs_to :box
  belongs_to :media
  belongs_to :recognition_run
  belongs_to :item, optional: true

  validates :proposed_name, presence: true
  validates :proposed_quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :state, inclusion: { in: STATES }
end
