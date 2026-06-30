# frozen_string_literal: true

module EmbeddingProviders
  # Voyage AI text embeddings, built per Move with that Move's own voyage_api_key
  # (#237 — per-Move BYO; EmbeddingProviders.for_move). Voyage is the embeddings
  # vendor Anthropic recommends (Anthropic has no first-party embeddings API), so
  # it is search-only — there is no recognition Voyage adapter and no shared key.
  #
  # voyage-3-large is a Matryoshka model whose output_dimension is one of
  # {256,512,1024,2048} — NOT 1536. We request 1024 (its default, highest-quality
  # supported width below the column size) and Base#fit_dimensions zero-pads it to
  # the fixed pgvector(1536) column. Zero-padding is cosine-preserving and a Move's
  # whole index is re-embedded on any space change, so ranking stays correct.
  # Not exercised in CI; never leaks the raw response.
  class Voyage < Base
    ENDPOINT = "https://api.voyageai.com/v1/embeddings"
    DEFAULT_MODEL = "voyage-3-large"
    # Native width requested from Voyage before padding to DIMENSIONS (1536).
    OUTPUT_DIMENSION = 1024

    def embed(text)
      return blank_result if text.to_s.strip.empty?

      json = post_json(
        ENDPOINT,
        headers: { "Authorization" => "Bearer #{api_key!}" },
        body: { model: DEFAULT_MODEL, input: text.to_s, output_dimension: OUTPUT_DIMENSION },
        read_timeout: 30
      )
      vector = json.dig("data", 0, "embedding")
      raise ProviderHttp::Error, "Voyage embedding response missing data" if vector.nil?

      Result.new(provider: provider_name, model: model_name, vector: fit_dimensions(vector))
    end

    private

    def provider_name = "voyage"
    def model_name = DEFAULT_MODEL
  end
end
