# frozen_string_literal: true

module Clusters
  # Recomputes a Move's item clusters (#629, PR 2 of #625): groups the
  # searchable items into families ("AA batteries — 9 items · 4 boxes") over
  # name embeddings. Full recompute per Move on purpose — at a few hundred
  # distinct names it is seconds of work, and re-deriving globally each run
  # keeps the result deterministic and drift-free (no incremental staleness
  # classes). Two stages:
  #
  #   1. EXACT — group items by normalized name (case/punctuation/plural
  #      folded). Identical names always cluster, whatever the provider.
  #   2. MERGE — embed each group's key_text (normalized name + modal hidden
  #      family, #626) once into the ClusterNameEmbedding cache, take pairwise
  #      cosine similarities with one exact self-join (no ANN), then run a
  #      greedy leader pass: biggest groups lead; a group joins the most
  #      similar existing leader it has a DIRECT edge to at/above the model's
  #      threshold. Direct-to-leader membership is the anti-chaining rule —
  #      "battery"→"charger"→"cable" must not fuse into one mush.
  #
  # Keyless Moves degrade through the same pipeline: EmbeddingProviders hands
  # them the Fake embedder, whose cosine ≈ token overlap, so they get
  # word-share families at a lower threshold while Stage 1 stays the floor.
  # (The Fake tokenizer is ASCII-only, so non-Latin names merge only via
  # Stage 1 on the keyless path — a real provider handles them semantically.)
  # Clustering never reads item_search_documents.embedding, so a whole-Move
  # re-embed (IndexingRuns' null-then-refill window) cannot corrupt it.
  #
  # Concurrency: the WHOLE run holds a per-Move session-level advisory lock —
  # taken before the working set is read, released after persist commits. A
  # racing run (rake vs the debounced job) therefore waits and then reads a
  # snapshot that already includes the winner's world: a stale earlier reader
  # can never overwrite fresher clusters (write-write collisions on the unique
  # indexes are prevented by the same serialization). The lock spans the
  # embed calls deliberately — no DB transaction is open during them, only the
  # lock, and serializing the cache fill per Move is desirable anyway. A Move
  # hard-deleted mid-run surfaces as Failure(:move_deleted), never a raw FK
  # raise. On a cold Move with a real provider the name-cache fill is one
  # serial embed call per distinct name (no batch API yet); partial progress
  # commits per name, so an interrupted run resumes from the misses.
  class Recompute < BaseAction
    # Advisory-lock namespace for cluster recomputes (the two-int
    # pg_advisory_lock form) — app-unique so other features' locks can't collide.
    LOCK_NAMESPACE = 625
    # Minimum cosine similarity (1 - distance) for a group to join a leader,
    # keyed by embedding model — vector spaces are never mixed. The fake
    # embedder's similarity is token overlap: two 2-token names sharing one
    # word score 0.5, so 0.45 keeps those merges while sitting ABOVE 0.408 —
    # the score a single 1536-bucket hash collision produces between unrelated
    # 2- and 3-token names ("battery"/"wooden" really collide, which put a
    # wooden coffee table in the demo's battery family at θ=0.4). 0.62 is a
    # conservative starting point for real semantic models, calibrated against
    # a real key in PR 4. Tuneable constants, not policy.
    MIN_SIMILARITY = Hash.new(0.62).merge("fake-embed-1" => 0.45).freeze

    # A family of one is noise — only clusters with at least this many member
    # items are persisted (no zero-value rows for the gallery to filter).
    MIN_CLUSTER_ITEMS = 2

    #: (move: untyped, ?embedder: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, embedder: nil)
      embedder ||= EmbeddingProviders.for_move(move)
      model = embedder.model

      with_move_lock(move) do
        groups = stage_one(move)
        ensure_vectors(move, groups, embedder, model)
        sims = similarity_lookup(move, groups, model)
        clusters = persist(move, leader_pass(groups, sims, model), model)
        emit_event(move, clusters)
        Success(clusters)
      end
    rescue ActiveRecord::InvalidForeignKey
      # The Move (or its items) was hard-deleted mid-run (Moves::Destroy
      # cascades every cluster table); nothing to recompute — the cascade
      # already cleaned up whatever we had written.
      Failure(:move_deleted)
    end

    private

    # Stage 1: one bounded SELECT of the searchable set, grouped by normalized
    # name in memory (a clustering working set — the sanctioned in-memory
    # group_by, not a DB-derivable aggregate). Blank normalizations are dropped
    # (a name of pure punctuation cannot be clustered meaningfully).

    #: (untyped move) -> Hash[String, untyped]
    def stage_one(move)
      rows = move.items.searchable.pluck(:id, :name, :box_id, :family)
      rows.group_by { |(_, name, _, _)| normalize(name) }.except("").to_h do |key, members|
        items = members.map { |(id, name, box_id, family)| { id: id, name: name, box_id: box_id, family: family } }
        [key, { key: key, items: items, key_text: key_text(key, items) }]
      end
    end

    # Case/punctuation/plural folding so "AA Batteries" ≡ "aa battery". Unicode
    # letters survive ([[:alnum:]]); singularize is per-token. Known inflector
    # quirk (accepted): some singular nouns ending in "s" get truncated
    # ("gas"→"ga", "lens"→"len") — identical inputs still normalize identically
    # so Stage 1's guarantee holds; the mangled stem only slightly degrades the
    # Stage-2 embedding for those words. Revisit with PR 4's calibration.

    #: (untyped name) -> String
    def normalize(name)
      name.to_s.downcase.gsub(/[^[:alnum:]]+/, " ").squish.split.map(&:singularize).join(" ")
    end

    # The embedded text: normalized name plus the group's modal hidden family
    # (#626) — the facet pulls vaguely-named items toward their true family.
    # Most-frequent non-blank family wins; ties break alphabetically for a
    # deterministic cache key.

    #: (String key, untyped items) -> String
    def key_text(key, items)
      families = items.filter_map { |item| item[:family].to_s.downcase.presence }
      modal = families.tally.min_by { |family, count| [-count, family] }&.first
      "#{key} #{modal}".squish
    end

    # Embed only cache misses — each distinct key_text costs one embed call,
    # ever, per vector space. An embed failure must not fail the recompute: the
    # group simply keeps no vector, forms no edges, and stands as its own
    # Stage-1 cluster (mirrors RefreshDocument#apply_embedding's degradation).
    # The write is an ON-CONFLICT-DO-NOTHING insert: a concurrent recompute (or
    # two groups sharing one key_text) can never crash the run on the unique
    # index — create! would re-raise the model's uniqueness validation as
    # RecordInvalid, which is exactly the race this shape closes.

    #: (untyped move, untyped groups, untyped embedder, String model) -> void
    def ensure_vectors(move, groups, embedder, model)
      texts = groups.values.pluck(:key_text).uniq
      cached = ClusterNameEmbedding.where(move: move, embedding_model: model, key_text: texts).pluck(:key_text)
      (texts - cached).each do |text|
        result = safe_embed(embedder, text)
        next unless result&.vector

        # Values are constructed here (never user-assigned); the unique index
        # is the invariant and the conflict target, so the fill is idempotent.
        ClusterNameEmbedding.insert(
          { move_id: move.id, embedding_model: model, key_text: text, embedding: result.vector },
          unique_by: :index_cluster_name_embeddings_on_move_model_text, record_timestamps: true
        )
      end
    end

    # The log line carries a digest fingerprint, never the text itself — the
    # key is customer inventory content (item name + hidden family) and must
    # not be retained in logs/error collectors on a provider outage. The
    # fingerprint still correlates a repeatedly-failing name across runs.

    #: (untyped embedder, String text) -> untyped
    def safe_embed(embedder, text)
      embedder.embed(text)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- degrade to Stage-1-only for this group, never fail the recompute
      fingerprint = Digest::SHA256.hexdigest(text)[0, 8]
      Rails.logger.warn("[clusters] name embedding failed (key sha=#{fingerprint}): #{e.class}: #{e.message}")
      nil
    end

    # All qualifying pairwise similarities in one exact self-join over the
    # Move's current-model vectors, restricted to this run's key_texts. Exact
    # (no HNSW) keeps the result deterministic; G ≤ ~1.5k names is ~1M distance
    # ops in C — comfortably a background job's work. Returns a lookup keyed by
    # the sorted key_text pair.

    #: (untyped move, untyped groups, String model) -> Hash[untyped, Float]
    def similarity_lookup(move, groups, model)
      texts = groups.values.pluck(:key_text).uniq
      return {} if texts.size < 2

      binds = { move_id: move.id, model: model, texts: texts, max_distance: 1.0 - MIN_SIMILARITY[model] }
      sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, binds])
        SELECT a.key_text, b.key_text, 1 - (a.embedding <=> b.embedding) AS sim
        FROM cluster_name_embeddings a
        JOIN cluster_name_embeddings b
          ON b.move_id = a.move_id AND b.embedding_model = a.embedding_model AND b.key_text < a.key_text
        WHERE a.move_id = :move_id AND a.embedding_model = :model
          AND a.key_text IN (:texts) AND b.key_text IN (:texts)
          AND (a.embedding <=> b.embedding) <= :max_distance
      SQL
      ActiveRecord::Base.connection.select_rows(sql).to_h do |(text_a, text_b, sim)|
        [[text_a, text_b].sort, sim.to_f]
      end
    end

    # Greedy leader pass. Deterministic: groups walk in [-item_count, name]
    # order; a group joins the most similar existing leader with a DIRECT edge
    # at/above threshold (tie → alphabetical leader), else becomes a leader
    # itself. Never transitive — that is the anti-chaining guarantee.

    #: (untyped groups, untyped sims, String model) -> Hash[String, untyped]
    def leader_pass(groups, sims, model)
      threshold = MIN_SIMILARITY[model]
      assignments = {} #: Hash[String, untyped]
      groups.values.sort_by { |group| [-group[:items].size, group[:key]] }.each do |group|
        leader = best_leader(group, assignments.keys, groups, sims, threshold)
        (assignments[leader || group[:key]] ||= []) << group
      end
      assignments
    end

    # The most similar existing leader this group has a DIRECT qualifying edge
    # to (tie → alphabetical leader), or nil when none qualifies.

    #: (untyped group, untyped leader_keys, untyped groups, untyped sims, Float threshold) -> String?
    def best_leader(group, leader_keys, groups, sims, threshold)
      qualifying = leader_keys.filter_map do |key|
        sim = similarity(groups.fetch(key), group, sims)
        [key, sim] if sim >= threshold
      end
      qualifying.min_by { |(key, sim)| [-sim, key] }&.first
    end

    # Two groups with identical key_texts are trivially identical in vector
    # space (they'd share a cache row) — treat as similarity 1.0 without an edge.

    #: (untyped left, untyped right, untyped sims) -> Float
    def similarity(left, right, sims)
      return 1.0 if left[:key_text] == right[:key_text]

      sims[[left[:key_text], right[:key_text]].sort] || 0.0
    end

    # Persist atomically: upsert clusters by (move_id, leader_key) so ids — and
    # gallery detail URLs — survive recomputes, delete vanished leaders (FKs
    # cascade their memberships), replace memberships wholesale, write the
    # denormalized counts from the same working set, and stamp completion — all
    # in ONE transaction. Cross-run collisions (leader_key/item_id unique
    # indexes, row-lock deadlocks, stale-reader-overwrites-fresh) are prevented
    # upstream by the whole-run session lock in #call. Everything queries
    # ItemCluster explicitly, never move.item_clusters: the association proxy
    # would cache a pre-deletion load on the CALLER's move, leaving it reading
    # retired clusters after the recompute.

    #: (untyped move, untyped assignments, String model) -> untyped
    def persist(move, assignments, model)
      kept = assignments.filter_map do |leader_key, groups|
        items = groups.flat_map { |group| group[:items] }
        { leader_key: leader_key, items: items } if items.size >= MIN_CLUSTER_ITEMS
      end

      ActiveRecord::Base.transaction do
        pairs = upsert_clusters(move, kept, model)
        ItemCluster.where(move_id: move.id).where.not(leader_key: kept.pluck(:leader_key)).delete_all
        replace_memberships(move, pairs)
        record_computed(move)
        pairs.map(&:last)
      end
    end

    # Session-level per-Move lock held for the WHOLE recompute (read → embed →
    # persist), so a waiting run's snapshot is always taken after the winner's
    # commit — a stale reader can never be the last writer (Codex P1 on #630).
    # Session (not xact) scope because the embed calls must not run inside a
    # DB transaction; the ensure releases on the same leased connection, and a
    # crashed session drops the lock automatically. hashtext folds the uuid to
    # int4; LOCK_NAMESPACE disambiguates from other features' advisory locks.

    #: (untyped move) { () -> untyped } -> untyped
    def with_move_lock(move)
      connection = ActiveRecord::Base.connection
      connection.execute(lock_sql("pg_advisory_lock", move))
      begin
        yield
      ensure
        connection.execute(lock_sql("pg_advisory_unlock", move))
      end
    end

    #: (String function, untyped move) -> String
    def lock_sql(function, move)
      ActiveRecord::Base.sanitize_sql_array(
        ["SELECT #{function}(:ns, hashtext(:move_id))", { ns: LOCK_NAMESPACE, move_id: move.id }]
      )
    end

    # Returns [kept-cluster, row] pairs so membership rows pair by identity —
    # never by array position.

    #: (untyped move, untyped kept, String model) -> untyped
    def upsert_clusters(move, kept, model)
      existing = ItemCluster.where(move_id: move.id).index_by(&:leader_key)
      kept.map do |cluster|
        row = existing[cluster[:leader_key]] || ItemCluster.new(move_id: move.id, leader_key: cluster[:leader_key])
        row.assign_attributes(
          label: label_for(cluster[:items]), embedding_model: model,
          items_count: cluster[:items].size,
          boxes_count: cluster[:items].map { |item| item[:box_id] }.uniq.size
        )
        row.save!
        [cluster, row]
      end
    end

    #: (untyped move, untyped pairs) -> void
    def replace_memberships(move, pairs)
      ItemClusterMembership.where(item_cluster_id: ItemCluster.where(move_id: move.id).select(:id)).delete_all
      now = Time.current
      memberships = pairs.flat_map do |(cluster, row)|
        cluster[:items].map do |item|
          { item_cluster_id: row.id, item_id: item[:id], created_at: now, updated_at: now }
        end
      end
      # rubocop:disable Rails/SkipsModelValidations -- bulk replace inside the
      # recompute transaction; rows are derived from just-validated clusters +
      # the working set, and the DB unique index on item_id is the invariant.
      ItemClusterMembership.insert_all(memberships) if memberships.any?
      # rubocop:enable Rails/SkipsModelValidations
    end

    # The cluster's human title: the raw member name people (or the model) used
    # most; ties prefer the shortest, then alphabetical — deterministic.

    #: (untyped items) -> String
    def label_for(items)
      items.map { |item| item[:name] }.tally.min_by { |name, count| [-count, name.length, name] }&.first.to_s
    end

    # Runs inside the persist transaction so fresh clusters and their
    # completion stamp commit atomically — a crash can't leave real clusters
    # behind a nil computed_at (the gallery's "organizing" state). Upsert keeps
    # refresh_pending/requested_at (PR 3's debounce fields) untouched — only
    # the completion timestamp is ours to write.

    #: (untyped move) -> void
    def record_computed(move)
      # rubocop:disable Rails/SkipsModelValidations -- atomic write-or-update of
      # the singleton's completion stamp; only computed_at is ours to touch
      # (refresh_pending/requested_at belong to the PR 3 debounce claim).
      ClusterState.upsert(
        { move_id: move.id, computed_at: Time.current },
        unique_by: :index_cluster_states_on_move_id, record_timestamps: true
      )
      # rubocop:enable Rails/SkipsModelValidations
    end

    #: (untyped move, untyped clusters) -> untyped
    def emit_event(move, clusters)
      Rails.event.notify("clusters.recomputed", move_id: move.id, cluster_count: clusters.size)
      Success()
    end
  end
end
