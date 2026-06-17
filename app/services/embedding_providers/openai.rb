# frozen_string_literal: true

module EmbeddingProviders
  # OpenAI text embeddings, built per Move with that Move's own openai_api_key
  # (#232 — per-Move BYO; EmbeddingProviders.for_move). Uses
  # text-embedding-3-small at 1536 dimensions to match the pgvector column. Not
  # exercised in CI; never leaks the raw response upward.
  class Openai < Base
    ENDPOINT = "https://api.openai.com/v1/embeddings"
    # The only model the fixed item_search_documents.embedding vector(1536) column
    # supports — NOT overridable per Move (unlike recognition's chat model). A
    # different dimension would need a column/HNSW rethink.
    DEFAULT_MODEL = "text-embedding-3-small"

    def embed(text)
      return blank_result if text.to_s.strip.empty?

      json = post_json(
        ENDPOINT,
        headers: { "Authorization" => "Bearer #{api_key!}" },
        body: { model: model_name, input: text.to_s, dimensions: DIMENSIONS },
        read_timeout: 30
      )
      vector = json.dig("data", 0, "embedding")
      raise ProviderHttp::Error, "OpenAI embedding response missing data" if vector.nil?

      Result.new(provider: provider_name, model: model_name, vector: vector.map(&:to_f))
    end

    private

    def provider_name = "openai"
    def model_name = DEFAULT_MODEL
  end
end
