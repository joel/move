# frozen_string_literal: true

module RecognitionProviders
  # Deterministic provider for tests and local development. Returns a fixed set of
  # detections spanning above- and below-threshold confidence so the auto-confirm
  # vs pending-review split is exercised without any external call. Each detection
  # also carries a category + fragility so the materialization path (and
  # /product-review) shows categorised, fragility-flagged items.
  class Fake < Base
    SAMPLE = [
      ["Coffee maker",   0.97, 1, "Kitchenware",  false],
      ["Stack of books", 0.88, 3, "Books",        false],
      ["Set of mugs",    0.62, 1, "Kitchenware",  true]
    ].freeze

    def identify(image:, context:) # rubocop:disable Lint/UnusedMethodArgument
      objects = SAMPLE.map do |label, confidence, count, category, fragile|
        DetectedObject.new(
          label: label, confidence: confidence, count: count,
          category: category, fragile: fragile
        )
      end
      Result.new(provider: "fake", provider_model: "fake-1", objects: objects)
    end
  end
end
