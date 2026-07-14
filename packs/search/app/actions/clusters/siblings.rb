# frozen_string_literal: true

# pack_public: true -- public API of packs/search: the item-detail "same group"
# rail read (ItemsController). See packwerk-boundaries.md for the sigil convention.

module Clusters
  # The rest of an item's family (#642): its cluster's other members, for the
  # "In the same group" rail on the item detail page. Live-filtered through
  # Item.searchable on BOTH sides — the siblings drop out when removed/unpacked
  # since the last recompute, and the rail is withheld entirely when the VIEWED
  # item has itself left the searchable set (a lingering membership from before
  # its own removal must not claim it's "in the group"). Box-ordered so the
  # rail reads like the group checklist; the item itself is excluded. Returns
  # nil when the item is in no live group — the common case for a manual item
  # or one whose name is unique — so the caller renders nothing.
  class Siblings < BaseAction
    Result = Data.define(:cluster, :items)

    #: (item: untyped) -> untyped
    def call(item:)
      membership = ItemClusterMembership.find_by(item_id: item.id)
      return nil unless membership && Item.searchable.exists?(id: item.id)

      cluster = membership.item_cluster
      items = cluster.items.merge(Item.searchable)
                     .where.not(id: item.id)
                     .includes(box: :room, source_media: { image_attachment: :blob })
                     .joins(:box)
                     .order(Arel.sql("boxes.number::bigint"), :name)
                     .to_a
      return nil if items.empty?

      Result.new(cluster: cluster, items: items)
    end
  end
end
