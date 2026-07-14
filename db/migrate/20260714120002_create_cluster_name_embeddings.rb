# frozen_string_literal: true

# Embed-once cache for clustering (#629). Clustering deliberately does NOT
# reuse item_search_documents.embedding — that vector embeds "name Box N room",
# whose box/room tokens systematically pull same-box items together, the exact
# opposite of "find the AA batteries scattered across four boxes". Instead each
# distinct key_text (normalized item name + modal hidden family, #626) is
# embedded once per vector space and cached here forever: a Move's thousands of
# items collapse to a few hundred distinct names, so a new name costs one embed
# call ever, and a whole-Move re-embed (IndexingRuns) can never race this table
# — Clusters::Recompute reads only its own cache.
#
# No HNSW index on purpose: the pairwise similarity pass is one exact self-join
# over ≤ ~1.5k rows per Move — deterministic, no ANN approximation.
#
# ⚠ Naming constraint: a tenant-schema table name must NOT contain any
# Apartment `pg_excluded_names` entry as a substring ("vector", "citext",
# "hstore", …). The tenant-clone rewrite (ros-apartment
# `swap_schema_qualifier`) skips every `public.X` match containing an excluded
# name, so a table named e.g. `cluster_name_vectors` would stay
# `public.`-qualified in the clone SQL and every Organizations::Create would
# fail with PG::DuplicateTable. Hence "embeddings", not "vectors".
class CreateClusterNameEmbeddings < ActiveRecord::Migration[8.1]
  def change
    create_table :cluster_name_embeddings, id: :uuid do |t|
      t.references :move, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :key_text, null: false
      t.string :embedding_model, null: false
      t.column :embedding, "vector(1536)", null: false
      t.timestamps
    end

    add_index :cluster_name_embeddings, %i[move_id embedding_model key_text],
              unique: true, name: "index_cluster_name_embeddings_on_move_model_text"
  end
end
