# frozen_string_literal: true

# Embed-once cache row for clustering (#629): one vector per distinct
# (move, embedding_model, key_text), where key_text = normalized item name +
# modal hidden family (#626). Private to packs/search — only
# Clusters::Recompute reads or writes it. See the migration for why clustering
# embeds names rather than reusing item_search_documents.embedding — and for
# why the table is named "embeddings": a tenant table name containing "vector"
# breaks Apartment's clone rewrite (pg_excluded_names substring skip).
class ClusterNameEmbedding < ApplicationRecord
  belongs_to :move

  validates :key_text, presence: true, uniqueness: { scope: %i[move_id embedding_model] }
  validates :embedding_model, presence: true
  validates :embedding, presence: true
end
