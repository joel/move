# frozen_string_literal: true

# pack_public: true -- public API of packs/search: the gallery Groups read
# (GalleriesController + the grid component render from it). See
# packwerk-boundaries.md for the sigil convention.

module Clusters
  # Everything the gallery Groups view needs in one read (#633): which state
  # the surface is in, the capped cluster cards ordered widest-spread-first
  # (scatter is the pain the feature answers), each card's preview thumbnails,
  # and its box-number chips — the retrieval payload. Read-only; never writes.
  class Overview < BaseAction
    # Safety valve for a pathological Move, mirroring the photo grid's CAP.
    CAP = 100
    # Thumbnails shown per card. The member window is wider so dedupe (several
    # items from one photo) and non-displayable images still leave enough.
    PREVIEWS_PER_CLUSTER = 4
    MEMBER_WINDOW = 8

    # status: :no_items (nothing searchable yet) · :organizing (never computed —
    # caller should request a refresh) · :none (computed, no family qualified) ·
    # :ready. previews/box_numbers are keyed by cluster id.
    Result = Data.define(:status, :clusters, :previews, :box_numbers, :capped)

    #: (move: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:)
      return Success(empty(:no_items)) unless move.items.searchable.exists?
      return Success(empty(:organizing)) unless computed?(move)

      rows = ItemCluster.where(move_id: move.id).by_spread.limit(CAP + 1).to_a
      capped = rows.size > CAP
      rows = rows.first(CAP)
      return Success(empty(:none)) if rows.empty?

      ids = rows.map(&:id)
      Success(Result.new(
                status: :ready, clusters: rows, capped: capped,
                previews: previews_for(ids), box_numbers: box_numbers_for(ids)
              ))
    end

    private

    #: (Symbol status) -> untyped
    def empty(status)
      Result.new(status: status, clusters: [], previews: {}, box_numbers: {}, capped: false)
    end

    #: (untyped move) -> bool
    def computed?(move)
      ClusterState.where(move_id: move.id).where.not(computed_at: nil).exists?
    end

    # ≤PREVIEWS_PER_CLUSTER distinct displayable member photos per card, found
    # with ONE window query (never all memberships of all clusters) and one
    # Media load. DISTINCT ON collapses duplicate source photos BEFORE the
    # window ranks them, so the window counts distinct photos — a box whose one
    # photo recognized a dozen members can't starve the quilt of the other
    # boxes' photos. The searchable guards are explicit because raw SQL
    # bypasses the default_scope and the scope; a photo that became
    # non-displayable since the recompute yields a shorter strip (bounded
    # staleness, self-heals next recompute).

    #: (untyped ids) -> Hash[untyped, untyped]
    def previews_for(ids)
      sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, { ids: ids, window: MEMBER_WINDOW }])
        SELECT ranked.item_cluster_id, ranked.source_media_id
        FROM (
          SELECT distinct_media.item_cluster_id, distinct_media.source_media_id,
                 ROW_NUMBER() OVER (
                   PARTITION BY distinct_media.item_cluster_id
                   ORDER BY distinct_media.box_id, distinct_media.id
                 ) AS rn
          FROM (
            SELECT DISTINCT ON (m.item_cluster_id, i.source_media_id)
                   m.item_cluster_id, i.source_media_id, i.box_id, i.id
            FROM item_cluster_memberships m
            JOIN items i ON i.id = m.item_id
            WHERE m.item_cluster_id IN (:ids)
              AND i.discarded_at IS NULL AND i.source_media_id IS NOT NULL
              AND i.presence_state = 'in_box'
              AND i.review_state IN ('confirmed', 'auto_confirmed')
            ORDER BY m.item_cluster_id, i.source_media_id, i.id
          ) distinct_media
        ) ranked
        WHERE ranked.rn <= :window
      SQL
      pairs = ActiveRecord::Base.connection.select_rows(sql)
      media = Media.where(id: pairs.map(&:last).uniq).index_by(&:id)
      pairs.group_by(&:first).transform_values do |rows|
        rows.filter_map { |(_, media_id)| media[media_id] }
            .select(&:image_displayable?).first(PREVIEWS_PER_CLUSTER)
      end
    end

    # The chip payload: every member box number per cluster, numerically
    # ordered in SQL (numbers are strings — a lexical sort puts "9" after
    # "10"). Bounded by the clusters on the page; the card truncates.

    #: (untyped ids) -> Hash[untyped, untyped]
    def box_numbers_for(ids)
      sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, { ids: ids }])
        SELECT DISTINCT m.item_cluster_id, b.number, b.number::bigint AS sort_key
        FROM item_cluster_memberships m
        JOIN items i ON i.id = m.item_id
        JOIN boxes b ON b.id = i.box_id
        WHERE m.item_cluster_id IN (:ids) AND i.discarded_at IS NULL
        ORDER BY b.number::bigint
      SQL
      ActiveRecord::Base.connection.select_rows(sql)
                        .group_by(&:first)
                        .transform_values { |rows| rows.map { |row| row[1] } }
    end
  end
end
