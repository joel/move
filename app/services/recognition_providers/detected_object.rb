# frozen_string_literal: true

module RecognitionProviders
  # A single normalized detection. There is deliberately no bounding box / crop
  # field (Domain §4.11, TF §10.4). `category` is the model's classification (a
  # move-vocabulary name or a new one, nil when blank); `tags` is the model's list
  # of descriptive tag names (move-vocabulary names or new ones, empty when none).
  # Fragility moved off the item onto the box (Phase A); per-item quantity/count
  # was removed (Phase B) — a moving inventory cares what's in a box, not how many.
  DetectedObject = Data.define(:label, :confidence, :category, :tags) do
    # Default tags to [] so a provider that omits the field still constructs.
    def initialize(label:, confidence:, category:, tags: [])
      super
    end
  end
end
