# frozen_string_literal: true

# Provider-agnostic text embeddings for D8 hybrid search (Domain §7.3 / §7.5;
# Technical Foundation §11.4). Domain code asks EmbeddingProviders for a vector;
# the selected adapter returns a normalized EmbeddingProviders::Result. Only
# textual metadata is ever embedded — raw images never are (Domain §7.5).
module EmbeddingProviders
  module_function

  # Build the embedder for a Move's configured search-embedding provider, using
  # *that Move's* own API key (#232/#237 — per-Move bring-your-own-key, mirroring
  # RecognitionProviders.for_move; no shared/ENV key). Only a Move that selected a
  # real provider (openai/gemini/voyage) AND stored that provider's own key gets
  # the real adapter; everything else (fake, or a real provider without its key)
  # falls back to the network-free Fake embedder, so search degrades gracefully to
  # lexical + trigram rather than erroring or mixing vector spaces.
  def for_move(move)
    return Fake.new unless move&.embedding_provider_ready?

    provider = move.embedding_provider
    resolve(provider, api_key: move.embedding_api_key_for(provider))
  end

  # Name → adapter instance (#237 — mirrors RecognitionProviders.resolve). Every
  # real adapter conforms its native vector to the fixed 1536-d column via
  # Base#fit_dimensions. An unknown/fake name falls back to the keyless Fake
  # embedder. A real adapter built with a blank key raises Base::MissingApiKey on
  # #embed (callers drop the semantic leg) — but for_move never hands one out.
  def resolve(name, api_key: nil)
    case name.to_s
    when "openai" then Openai.new(api_key:)
    when "gemini" then Gemini.new(api_key:)
    when "voyage" then Voyage.new(api_key:)
    else Fake.new
    end
  end
end
