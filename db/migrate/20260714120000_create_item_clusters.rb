# frozen_string_literal: true

# Cluster rows for the gallery Groups view (#629, PR 2 of #625): one row per
# family of related items within a Move ("AA batteries — 9 items · 4 boxes").
# Computed by Clusters::Recompute over name embeddings; `leader_key` is the
# normalized name of the cluster's leader group and the row's stable identity
# across recomputes (detail URLs survive most recomputations). Counts are
# denormalized at recompute time so the gallery sorts join-free. Lives in the
# tenant schema like every Move-owned record; move FK cascades so
# Moves::Destroy needs no change (same pattern as item_search_documents).
class CreateItemClusters < ActiveRecord::Migration[8.1]
  def change
    create_table :item_clusters, id: :uuid do |t|
      t.references :move, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :leader_key, null: false
      t.string :label, null: false
      t.integer :items_count, null: false, default: 0
      t.integer :boxes_count, null: false, default: 0
      t.string :embedding_model, null: false
      t.timestamps
    end

    add_index :item_clusters, %i[move_id leader_key], unique: true
    # The gallery's default order: widest box-spread first, then size.
    add_index :item_clusters, %i[move_id boxes_count items_count]
  end
end
