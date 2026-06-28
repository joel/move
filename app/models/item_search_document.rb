# frozen_string_literal: true

# D8 hybrid-search projection of an Item (Technical Foundation §11). Holds the
# denormalized `search_text` (item name + box number + room),
# a generated `search_tsvector` for full-text, and an optional pgvector
# `embedding` for semantic search. Lexical/trigram search works without the
# embedding, so it is nullable and (re)generated asynchronously. Lives in the
# tenant schema; scoped by move_id.
class ItemSearchDocument < ApplicationRecord
  has_neighbors :embedding

  belongs_to :item
  belongs_to :move

  # Rows whose embedding is present (drives the semantic leg; the rest fall back
  # to lexical/trigram only).
  scope :embedded, -> { where.not(embedding: nil) }
end
