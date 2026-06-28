# frozen_string_literal: true

module RecognitionProviders
  # A single normalized detection. `count` is the number of identical instances;
  # there is deliberately no bounding box / crop field (Domain §4.11, TF §10.4).
  # `category` is the model's classification (a move-vocabulary name or a new
  # one, nil when blank); `tags` is the model's list of descriptive tag names
  # (move-vocabulary names or new ones, empty when none). Fragility moved off the
  # item onto the box (a manual flag) in Phase A, so it is no longer detected.
  DetectedObject = Data.define(:label, :confidence, :count, :category, :tags) do
    # Default tags to [] so a provider that omits the field still constructs.
    def initialize(label:, confidence:, count:, category:, tags: [])
      super
    end
  end
end
