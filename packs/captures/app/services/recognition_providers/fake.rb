# frozen_string_literal: true

module RecognitionProviders
  # Deterministic provider for tests and local development. Returns a fixed set of
  # detections spanning above- and below-threshold confidence so the auto-confirm
  # vs pending-review split is exercised without any external call.
  class Fake < Base
    # Families exercise the hidden facet (#626): two share one ("kitchenware")
    # so search/cluster enrichment is demonstrable, one has none (an unsure
    # model returns blank → nil) so the absent path stays covered.
    SAMPLE = [
      { label: "Coffee maker",   confidence: 0.97, family: "kitchenware" },
      { label: "Stack of books", confidence: 0.88, family: nil },
      { label: "Set of mugs",    confidence: 0.62, family: "kitchenware" }
    ].freeze

    def identify(image:, context:) # rubocop:disable Lint/UnusedMethodArgument
      objects = SAMPLE.map { |attrs| DetectedObject.new(**attrs) }
      Result.new(provider: "fake", provider_model: "fake-1", objects: objects)
    end
  end
end
