# frozen_string_literal: true

module RecognitionProviders
  # Deterministic provider for tests and local development. Returns a fixed set of
  # detections spanning above- and below-threshold confidence so the auto-confirm
  # vs pending-review split is exercised without any external call.
  class Fake < Base
    SAMPLE = [
      ["Coffee maker", 0.97, 1],
      ["Stack of books", 0.88, 3],
      ["Set of mugs", 0.62, 1]
    ].freeze

    def identify(image:, context:) # rubocop:disable Lint/UnusedMethodArgument
      objects = SAMPLE.map do |label, confidence, count|
        DetectedObject.new(label: label, confidence: confidence, count: count)
      end
      Result.new(provider: "fake", provider_model: "fake-1", objects: objects)
    end
  end
end
