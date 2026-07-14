# frozen_string_literal: true

# Joins an Item into its ItemCluster (#629). An item belongs to at most one
# cluster (DB-unique item_id) — clustering partitions the searchable set. Rows
# are replaced wholesale by Clusters::Recompute; both FKs cascade so item/Move
# deletion needs no cluster awareness. Public alongside ItemCluster so the
# gallery (PR 4) and the item-detail rail (PR 5) can traverse memberships.
class ItemClusterMembership < ApplicationRecord
  belongs_to :item_cluster, inverse_of: :memberships
  belongs_to :item

  validates :item_id, uniqueness: true
end
