# frozen_string_literal: true

# pack_public: true -- public API of packs/search: the group-detail read
# (GalleryGroupsController). See packwerk-boundaries.md for the sigil convention.

module Clusters
  # A cluster and its member items for the group-detail page (#633). Members
  # are filtered LIVE through Item.searchable — an item removed or discarded
  # since the last recompute drops out immediately even while the denormalized
  # counts are ~a-debounce stale — and ordered by box number then name: the
  # detail page is an unpacking checklist, so you sweep one box at a time.
  class Members < BaseAction
    # Field is :items (not :members) — :members would shadow Ruby's Data#members.
    Result = Data.define(:cluster, :items)

    #: (move: untyped, cluster_id: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, cluster_id:)
      cluster = ItemCluster.find_by(id: cluster_id, move_id: move.id)
      return Failure(:not_found) unless cluster

      items = cluster.items.merge(Item.searchable)
                     .includes(:source_media, box: :room)
                     .joins(:box)
                     .order(Arel.sql("boxes.number::bigint"), :name)
                     .to_a
      Success(Result.new(cluster: cluster, items: items))
    end
  end
end
