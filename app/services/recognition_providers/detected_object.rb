# frozen_string_literal: true

module RecognitionProviders
  # A single normalized detection. `count` is the number of identical instances;
  # there is deliberately no bounding box / crop field (Domain §4.11, TF §10.4).
  # `category` is the model's classification (a move-vocabulary name or a new
  # one, nil when blank); `fragile` is the model's breakability call; `tags` is
  # the model's list of descriptive tag names (move-vocabulary names or new
  # ones, empty when none).
  DetectedObject = Data.define(:label, :confidence, :count, :category, :fragile, :tags) do
    # Default tags to [] so a provider that omits the field still constructs.
    def initialize(label:, confidence:, count:, category:, fragile:, tags: [])
      super
    end
  end
end
