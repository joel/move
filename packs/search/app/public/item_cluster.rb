# frozen_string_literal: true

# A family of related items within a Move (#629, PR 2 of #625) — "AA batteries,
# 9 items across 4 boxes" — computed by Clusters::Recompute over name
# embeddings, never user-managed (the #411 taxonomy stays dead). `leader_key`
# (the normalized name of the leader group) is the stable identity a recompute
# upserts by, so gallery detail URLs survive most recomputations; `label` is the
# human title (modal raw member name); counts are denormalized at recompute time
# so the gallery sorts join-free. Public API of packs/search: the gallery (PR 4)
# reads clusters through this model.
class ItemCluster < ApplicationRecord
  belongs_to :move

  has_many :memberships, class_name: "ItemClusterMembership", dependent: :delete_all, inverse_of: :item_cluster
  has_many :items, through: :memberships

  validates :leader_key, presence: true, uniqueness: { scope: :move_id }
  validates :label, presence: true
  validates :embedding_model, presence: true

  # Widest box-spread first — the scattered families are the product's payoff —
  # then size, then label for a stable page.
  scope :by_spread, -> { order(boxes_count: :desc, items_count: :desc, label: :asc) }
end
