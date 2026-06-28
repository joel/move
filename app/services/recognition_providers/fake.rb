# frozen_string_literal: true

module RecognitionProviders
  # Deterministic provider for tests and local development. Returns a fixed set of
  # detections spanning above- and below-threshold confidence so the auto-confirm
  # vs pending-review split is exercised without any external call. Each detection
  # also carries a category + tags so the materialization path (and
  # /product-review) shows categorised, tagged items. Tags span the matched (an
  # existing item-applicable default) and empty cases.
  class Fake < Base
    SAMPLE = [
      { label: "Coffee maker",   confidence: 0.97, count: 1, category: "Kitchenware", tags: %w[Heavy] },
      { label: "Stack of books", confidence: 0.88, count: 3, category: "Books",       tags: %w[Heavy] },
      { label: "Set of mugs",    confidence: 0.62, count: 1, category: "Kitchenware", tags: [] }
    ].freeze

    def identify(image:, context:) # rubocop:disable Lint/UnusedMethodArgument
      objects = SAMPLE.map { |attrs| DetectedObject.new(**attrs) }
      Result.new(provider: "fake", provider_model: "fake-1", objects: objects)
    end
  end
end
