# frozen_string_literal: true

module RecognitionProviders
  # A single normalized detection: just the model's `label` + its `confidence`.
  # There is deliberately no bounding box / crop field (Domain §4.11, TF §10.4).
  # The item has been pared down to its name across the simplification epic:
  # fragility moved to the box (Phase A), quantity/count removed (Phase B), and
  # category/tags removed (Phase C) — a moving inventory cares what's in a box.
  DetectedObject = Data.define(:label, :confidence)
end
