# frozen_string_literal: true

module RecognitionProviders
  # The vendor-independent result returned by every adapter — `provider` and
  # `provider_model` are labels only, `objects` is an Array<DetectedObject>.
  Result = Data.define(:provider, :provider_model, :objects)
end
