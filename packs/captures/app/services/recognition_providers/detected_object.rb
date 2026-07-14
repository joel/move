# frozen_string_literal: true

module RecognitionProviders
  # A single normalized detection: the model's `label` + its `confidence`, plus a
  # hidden `family` — a short generic phrase ("batteries & power") for the kind of
  # thing the item is (#626). The family is invisible metadata: never rendered,
  # only folded into the search projection text (and the cluster engine, #625);
  # nil when the model was unsure. The visible item itself stays just a name —
  # fragility moved to the box (Phase A), quantity/count removed (Phase B), and
  # category/tags removed (Phase C/#411) across the simplification epic. There is
  # deliberately no bounding box / crop field (Domain §4.11, TF §10.4).
  DetectedObject = Data.define(:label, :confidence, :family)
end
