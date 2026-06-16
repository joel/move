# frozen_string_literal: true

# Provider-agnostic text embeddings for D8 hybrid search (Domain §7.3 / §7.5;
# Technical Foundation §11.4). Domain code asks EmbeddingProviders for a vector;
# the selected adapter returns a normalized EmbeddingProviders::Result. Only
# textual metadata is ever embedded — raw images never are (Domain §7.5).
module EmbeddingProviders
  module_function

  # Build the embedder for a Move's configured search-embedding provider, using
  # *that Move's* own API key (#232 — per-Move bring-your-own-key, mirroring
  # RecognitionProviders.for_move; no shared/ENV key). Only a Move that selected
  # "openai" AND stored its own openai_api_key gets the real adapter; everything
  # else (fake, or openai without a key) falls back to the network-free Fake
  # embedder, so search degrades gracefully to lexical + trigram rather than
  # erroring or mixing vector spaces.
  def for_move(move)
    if move&.embedding_provider_ready?
      Openai.new(api_key: move.openai_api_key)
    else
      Fake.new
    end
  end
end
