# frozen_string_literal: true

module Search
  # Move-scoped hybrid item search (Domain §7; Technical Foundation §11.4).
  # Combines full-text (tsvector), trigram fuzzy (pg_trgm), and semantic
  # (pgvector cosine) signals with an exact-match boost, over the
  # item_search_documents projection. Degrades to lexical/trigram when no query
  # embedding is available (provider off / blank). Excludes needs_correction,
  # removed, and false-positive items unless `include_hidden:` is set (§7.4).
  #
  # Returns Success(Array<Result>) ordered best-first. Each Result carries the
  # item plus its box number, room, and a match explanation.
  class Items < BaseAction
    Result = Data.define(:item, :box_number, :room_name, :score, :matched_on)

    LIMIT = 50
    TRGM_THRESHOLD = 0.2          # min trigram similarity to qualify as a match
    SEMANTIC_MAX_DISTANCE = 0.55  # max cosine distance to qualify semantically
    WEIGHTS = { lexical: 1.0, trigram: 0.6, name: 1.0, semantic: 0.8, exact: 2.0 }.freeze

    def call(move:, query:, include_hidden: false, embedder: nil)
      q = query.to_s.strip
      return Success([]) if q.blank?

      # Embed the query with this Move's own provider (#232) so the query vector
      # lives in the same space as the stored item vectors. A fake/keyless Move
      # yields the Fake embedder; the semantic leg is dropped only when the vector
      # is nil (blank query / provider failure).
      embedder ||= EmbeddingProviders.for_move(move)

      vector, model = safe_query_embedding(embedder, q)
      rows = run(move, q, vector, model, include_hidden)
      Success(rows.map { |r| to_result(r) })
    end

    private

    # A query-embedding failure must not 500 the search — drop the semantic leg
    # and serve lexical/trigram results (Domain §7.3 graceful fallback). Returns
    # [vector, model] so the semantic leg can be pinned to the current provider's
    # model (#251); [nil, nil] drops the leg entirely.
    def safe_query_embedding(embedder, query)
      result = embedder.embed(query)
      result.vector ? [result.vector, result.model] : [nil, nil]
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §7.3 drop semantic leg, serve lexical
      Rails.logger.warn("[search] query embedding failed: #{e.class}: #{e.message}")
      [nil, nil]
    end

    def run(move, query, vector, model, include_hidden)
      scope = include_hidden ? move.items : move.items.searchable
      scope
        .joins(:search_document, :box)
        .joins("LEFT JOIN rooms ON rooms.id = boxes.room_id")
        .select(Arel.sql(sanitize(select_sql(vector), query, vector, model)))
        .where(match_sql(vector), **binds(query, vector, model))
        .order(Arel.sql("score DESC"))
        .limit(LIMIT)
    end

    # AR's `.select` does not bind params (only `.where` does), so the SELECT is
    # sanitized here. `CAST(:vec AS vector)` is used instead of `::vector` because
    # `::` collides with Rails' `:name` placeholder parsing.
    def sanitize(sql, query, vector, model)
      ActiveRecord::Base.sanitize_sql_array([sql, binds(query, vector, model)])
    end

    def select_sql(vector)
      lexical = "ts_rank_cd(item_search_documents.search_tsvector, plainto_tsquery('english', :q))"
      trigram = "similarity(item_search_documents.search_text, :q)"
      # Name trigram (focused, undiluted by box/room context) — drives
      # fuzzy recall on the most important field, e.g. "blow dryer" ~ "Hair dryer".
      name = "similarity(items.name, :q)"
      semantic = vector ? semantic_score_sql : "0.0"
      exact = "(CASE WHEN item_search_documents.search_text ILIKE :exact OR items.name ILIKE :exact " \
              "THEN 1 ELSE 0 END)"
      <<~SQL.squish
        items.*,
        boxes.number AS result_box_number,
        rooms.name AS result_room_name,
        #{lexical} AS lexical_score,
        GREATEST(#{trigram}, #{name}) AS trigram_score,
        #{semantic} AS semantic_score,
        #{exact} AS exact_hit,
        (#{lexical} * #{WEIGHTS[:lexical]} + #{trigram} * #{WEIGHTS[:trigram]}
         + #{name} * #{WEIGHTS[:name]} + #{semantic} * #{WEIGHTS[:semantic]}
         + #{exact} * #{WEIGHTS[:exact]}) AS score
      SQL
    end

    def match_sql(vector)
      conditions = [
        "item_search_documents.search_tsvector @@ plainto_tsquery('english', :q)",
        "similarity(item_search_documents.search_text, :q) >= #{TRGM_THRESHOLD}",
        "similarity(items.name, :q) >= #{TRGM_THRESHOLD}",
        "item_search_documents.search_text ILIKE :exact"
      ]
      conditions << semantic_match_sql if vector
      "(#{conditions.join(" OR ")})"
    end

    # Only trust a stored vector embedded with the SAME model as the current query
    # (#251). A whole-Move re-embed can race a provider/key change so a row keeps a
    # stale-space vector; pinning to embedding_model = :model ignores it (the row
    # degrades to lexical/trigram) instead of mis-ranking it against a query vector
    # from a different space.
    def semantic_match_clause
      "item_search_documents.embedding IS NOT NULL AND item_search_documents.embedding_model = :model"
    end

    def semantic_score_sql
      "(CASE WHEN #{semantic_match_clause} " \
        "THEN 1 - (item_search_documents.embedding <=> CAST(:vec AS vector)) ELSE 0 END)"
    end

    def semantic_match_sql
      "(#{semantic_match_clause} " \
        "AND (item_search_documents.embedding <=> CAST(:vec AS vector)) <= #{SEMANTIC_MAX_DISTANCE})"
    end

    def binds(query, vector, model)
      h = { q: query, exact: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%" }
      if vector
        h[:vec] = "[#{vector.map { |f| f.to_f.round(8) }.join(",")}]"
        h[:model] = model
      end
      h
    end

    def to_result(record)
      Result.new(
        item: record,
        box_number: record.read_attribute("result_box_number"),
        room_name: record.read_attribute("result_room_name"),
        score: record.read_attribute("score").to_f.round(4),
        matched_on: matched_on(record)
      )
    end

    # Strongest signal that qualified, for the UI's match explanation.
    def matched_on(record)
      return :exact if record.read_attribute("exact_hit").to_i == 1
      return :lexical if record.read_attribute("lexical_score").to_f.positive?
      return :semantic if record.read_attribute("semantic_score").to_f >= record.read_attribute("trigram_score").to_f

      :fuzzy
    end
  end
end
