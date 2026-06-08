# frozen_string_literal: true

module EmbeddingProviders
  # Adapter contract. Subclasses turn a text string into a normalized Result with
  # a DIMENSIONS-long vector. The dimension is fixed across providers so the
  # pgvector column type (vector(1536)) and stored embeddings stay compatible.
  class Base
    DIMENSIONS = 1536

    # @param text [String]
    # @return [EmbeddingProviders::Result] (vector may be nil for blank input)
    def embed(text)
      raise NotImplementedError, "#{self.class} must implement #embed"
    end

    protected

    def blank_result
      Result.new(provider: provider_name, model: model_name, vector: nil)
    end

    def l2_normalize(vector)
      norm = Math.sqrt(vector.sum { |x| x * x })
      norm.zero? ? vector : vector.map { |x| x / norm }
    end
  end
end
