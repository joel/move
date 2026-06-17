# frozen_string_literal: true

module EmbeddingProviders
  # Google Gemini text embeddings, built per Move with that Move's own
  # gemini_api_key (#237 — per-Move BYO; EmbeddingProviders.for_move; reuses the
  # same key as recognition's Gemini adapter). gemini-embedding-001 supports
  # Matryoshka output via outputDimensionality, so we request 1536 to match the
  # pgvector column directly. Google's guidance: embeddings at any width other
  # than the native 3072 are NOT pre-normalized, so we L2-normalize ourselves
  # (Base#fit_dimensions). Not exercised in CI; never leaks the raw response.
  class Gemini < Base
    HOST = "https://generativelanguage.googleapis.com/v1beta"
    # The only model + width the fixed item_search_documents.embedding vector(1536)
    # column supports — not overridable per Move (unlike recognition's chat model).
    DEFAULT_MODEL = "gemini-embedding-001"

    def embed(text)
      return blank_result if text.to_s.strip.empty?

      json = post_json(
        "#{HOST}/models/#{DEFAULT_MODEL}:embedContent",
        headers: { "x-goog-api-key" => api_key! },
        body: {
          model: "models/#{DEFAULT_MODEL}",
          content: { parts: [{ text: text.to_s }] },
          outputDimensionality: DIMENSIONS
        },
        read_timeout: 30
      )
      vector = json.dig("embedding", "values")
      raise ProviderHttp::Error, "Gemini embedding response missing values" if vector.nil?

      Result.new(provider: provider_name, model: model_name, vector: fit_dimensions(vector))
    end

    private

    def provider_name = "gemini"
    def model_name = DEFAULT_MODEL
  end
end
