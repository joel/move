# frozen_string_literal: true

module RecognitionProviders
  # Deterministic provider for tests and local development. Returns a fixed set of
  # detections spanning above- and below-threshold confidence so the auto-confirm
  # vs pending-review split is exercised without any external call.
  class Fake < Base
    SAMPLE = [
      { label: "Coffee maker",   confidence: 0.97 },
      { label: "Stack of books", confidence: 0.88 },
      { label: "Set of mugs",    confidence: 0.62 }
    ].freeze

    def identify(image:, context:) # rubocop:disable Lint/UnusedMethodArgument
      objects = SAMPLE.map { |attrs| DetectedObject.new(**attrs) }
      Result.new(provider: "fake", provider_model: "fake-1", objects: objects)
    end
  end
end
