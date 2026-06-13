# frozen_string_literal: true

module RecognitionProviders
  # A single normalized detection. `count` is the number of identical instances;
  # there is deliberately no bounding box / crop field (Domain §4.11, TF §10.4).
  # `category` is the model's classification (a move-vocabulary name or a new
  # one, nil when blank); `fragile` is the model's breakability call.
  DetectedObject = Data.define(:label, :confidence, :count, :category, :fragile)
end
