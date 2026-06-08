# frozen_string_literal: true

require "net/http"
require "json"

module EmbeddingProviders
  # OpenAI text embeddings (selected with EMBEDDING_PROVIDER=openai). Uses
  # text-embedding-3-small at 1536 dimensions to match the pgvector column. Not
  # exercised in CI; never leaks the raw response upward.
  class Openai < Base
    ENDPOINT = "https://api.openai.com/v1/embeddings"

    def embed(text)
      return blank_result if text.to_s.strip.empty?

      key = ENV["OPENAI_API_KEY"].presence or raise "OPENAI_API_KEY is not set"
      json = post(key, model: model_name, input: text.to_s, dimensions: DIMENSIONS)
      vector = json.dig("data", 0, "embedding")
      raise "OpenAI embedding response missing data" if vector.nil?

      Result.new(provider: provider_name, model: model_name, vector: vector.map(&:to_f))
    end

    private

    def provider_name = "openai"
    def model_name = ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")

    def post(key, body)
      uri = URI(ENDPOINT)
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{key}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        http.request(req)
      end
      JSON.parse(res.body)
    end
  end
end
