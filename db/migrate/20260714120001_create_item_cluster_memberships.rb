# frozen_string_literal: true

# Membership join for item clusters (#629): which items form each family. An
# item belongs to at most one cluster (unique item FK) — clustering partitions
# the searchable set. Both FKs cascade: deleting an item (or its Move / a
# recompute deleting a retired cluster) silently drops the membership, so
# neither Items::Delete nor Moves::Destroy needs to know clusters exist.
class CreateItemClusterMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :item_cluster_memberships, id: :uuid do |t|
      t.references :item_cluster, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :item, type: :uuid, null: false,
                          foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.timestamps
    end
  end
end
