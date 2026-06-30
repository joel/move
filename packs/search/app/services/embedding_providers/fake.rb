# frozen_string_literal: true

require "digest"

module EmbeddingProviders
  # Deterministic, network-free embedder for tests and local development. Uses
  # signed feature hashing of word tokens into a fixed-dimension, L2-normalized
  # vector: texts that share tokens get a higher cosine similarity, so synonym/
  # overlap recovery (e.g. "blow dryer" ~ "hair dryer", sharing "dryer") is
  # demonstrable without any API call. Not a real semantic model — precise
  # semantic ranking is exercised in specs with controlled vectors.
  class Fake < Base
    def embed(text)
      toks = tokens(text)
      return blank_result if toks.empty?

      vector = Array.new(DIMENSIONS, 0.0)
      toks.each do |tok|
        vector[index_for(tok)] += sign_for(tok)
      end
      Result.new(provider: provider_name, model: model_name, vector: l2_normalize(vector))
    end

    private

    def provider_name = "fake"
    def model_name = "fake-embed-1"

    def tokens(text)
      text.to_s.downcase.scan(/[a-z0-9]+/)
    end

    def index_for(token)
      Digest::SHA256.hexdigest(token).to_i(16) % DIMENSIONS
    end

    # Signed hashing reduces collisions cancelling vs reinforcing arbitrarily.
    def sign_for(token)
      Digest::SHA256.hexdigest("sign:#{token}").to_i(16).even? ? 1.0 : -1.0
    end
  end
end
