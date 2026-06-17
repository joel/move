# frozen_string_literal: true

# Voyage AI search-embedding key (#237). Voyage is the embeddings vendor Anthropic
# recommends and the third selectable semantic-search provider; it has no
# recognition counterpart, so unlike openai/gemini it needs its own key column.
# Encrypted at rest via ActiveRecord::Encryption (Move#encrypts), stored as text
# (ciphertext is longer than the raw key), and — like the other provider keys —
# NOT tracked by Logidze (its include-list excludes the key columns).
class AddVoyageApiKeyToMoves < ActiveRecord::Migration[8.1]
  def change
    add_column :moves, :voyage_api_key, :text
  end
end
