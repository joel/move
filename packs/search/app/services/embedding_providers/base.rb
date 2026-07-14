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

    # The model tag this embedder pins its vectors to (what Result#model and
    # item_search_documents.embedding_model carry). Public so a caller can key a
    # cache by vector space before embedding anything — the cluster name-vector
    # cache (#629) needs the space up front to know which rows are hits.
    def model
      model_name
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

    # Coerce a vendor's native vector to exactly DIMENSIONS, then L2-normalize, so
    # every provider feeds the fixed pgvector(1536) column regardless of its native
    # width (#237 — Voyage emits 1024, Gemini 1536, OpenAI 1536). A shorter vector
    # is **zero-padded** on the right; a longer one is truncated.
    #
    # Zero-padding is *exactly cosine-preserving*: for a' = [a, 0…] and b' = [b, 0…],
    # dot(a', b') == dot(a, b) and ‖a'‖ == ‖a‖, so cos(a', b') == cos(a, b). Because
    # reembed_move nulls and refills a Move's *whole* index on any space change, the
    # stored item vectors and the query vector always share one provider/width/pad,
    # so cosine ranking stays meaningful within a Move. (Truncation only fires for a
    # hypothetical >1536-d model and is the lossy branch — none of OpenAI/Gemini/
    # Voyage as configured hit it.)
    def fit_dimensions(vector)
      sized =
        if vector.length >= DIMENSIONS
          vector.first(DIMENSIONS)
        else
          vector + Array.new(DIMENSIONS - vector.length, 0.0)
        end
      l2_normalize(sized.map(&:to_f))
    end
  end
end
