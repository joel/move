# frozen_string_literal: true

module EmbeddingProviders
  # OpenAI text embeddings (selected with EMBEDDING_PROVIDER=openai). Uses
  # text-embedding-3-small at 1536 dimensions to match the pgvector column. Not
  # exercised in CI; never leaks the raw response upward.
  class Openai < Base
    ENDPOINT = "https://api.openai.com/v1/embeddings"

    def embed(text)
      return blank_result if text.to_s.strip.empty?

      key = ENV["OPENAI_API_KEY"].presence or raise "OPENAI_API_KEY is not set"
      json = post_json(
        ENDPOINT,
        headers: { "Authorization" => "Bearer #{key}" },
        body: { model: model_name, input: text.to_s, dimensions: DIMENSIONS },
        read_timeout: 30
      )
      vector = json.dig("data", 0, "embedding")
      raise ProviderHttp::Error, "OpenAI embedding response missing data" if vector.nil?

      Result.new(provider: provider_name, model: model_name, vector: vector.map(&:to_f))
    end

    private

    def provider_name = "openai"
    def model_name = ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
  end
end
