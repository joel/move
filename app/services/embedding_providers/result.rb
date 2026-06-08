# frozen_string_literal: true

module EmbeddingProviders
  # Vendor-independent embedding result. `vector` is an Array<Float> of length
  # DIMENSIONS, or nil when the input had nothing embeddable (blank text).
  Result = Data.define(:provider, :model, :vector)
end
