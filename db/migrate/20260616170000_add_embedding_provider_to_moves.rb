# frozen_string_literal: true

# Per-Move embedding provider configuration (#232, mirrors recognition #185).
# Moves D8 search embeddings from a single app-wide ENV setting
# (EMBEDDING_PROVIDER + OPENAI_API_KEY) to per-Move bring-your-own-key:
#   - embedding_provider: which embedder is active for this Move. Defaults to
#     "fake" (network-free, no key) so existing Moves never silently bill a shared
#     account after the cutover — an admin must opt into "openai" + a key.
# There is NO new key column: embeddings reuse the Move's existing encrypted
# openai_api_key (recognition #185), since OpenAI is the only real embedding
# provider (text-embedding-3-small @ 1536d, matching the fixed pgvector column).
class AddEmbeddingProviderToMoves < ActiveRecord::Migration[8.1]
  def change
    add_column :moves, :embedding_provider, :string, null: false, default: "fake"
  end
end
