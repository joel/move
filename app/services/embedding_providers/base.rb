# frozen_string_literal: true

module EmbeddingProviders
  # Adapter contract. Subclasses turn a text string into a normalized Result with
  # a DIMENSIONS-long vector. The dimension is fixed across providers so the
  # pgvector column type (vector(1536)) and stored embeddings stay compatible.
  class Base
    include ProviderHttp

    DIMENSIONS = 1536

    # Raised when a vendor adapter is asked to embed without this Move's own key.
    # Strict BYO: the adapter never reaches for a shared/ENV credential. Caught by
    # the callers (RefreshDocument#apply_embedding / Items#safe_query_vector),
    # which drop the semantic leg and keep lexical+trigram search working.
    class MissingApiKey < StandardError; end

    # Adapters are built per Move with that Move's key (EmbeddingProviders
    # .for_move). Fake needs none; Openai requires one (#embed raises otherwise).
    def initialize(api_key: nil)
      @api_key = api_key.presence
    end

    # @param text [String]
    # @return [EmbeddingProviders::Result] (vector may be nil for blank input)
    def embed(text)
      raise NotImplementedError, "#{self.class} must implement #embed"
    end

    protected

    # The Move's key, or a typed failure (never a shared/ENV key).
    def api_key!
      @api_key or raise MissingApiKey, "No API key set for #{self.class.name.demodulize}"
    end

    def blank_result
      Result.new(provider: provider_name, model: model_name, vector: nil)
    end

    def l2_normalize(vector)
      norm = Math.sqrt(vector.sum { |x| x * x })
      norm.zero? ? vector : vector.map { |x| x / norm }
    end
  end
end
