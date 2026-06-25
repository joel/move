# frozen_string_literal: true

module Searches
  # #338 — Per-browser memory of a Move's recent successful searches, so the
  # /search empty state can surface the user's own queries instead of static
  # placeholder examples (ux-conventions principles 4 & 1).
  #
  # Backed by the Rails session (no DB, no events — a read-only UX nicety), keyed
  # by Move id so different Moves don't bleed into each other. Stores at most
  # MAX queries per Move, most-recent-first, deduped case-insensitively.
  #
  # Bounded on every axis so it can never overflow the 4KB cookie session
  # (#338): queries longer than MAX_BYTES are clamped, at most MAX per Move, and
  # at most MAX_MOVES Moves are tracked (least-recently-used Move evicted first).
  # Worst case MAX_MOVES * MAX * MAX_BYTES bytes of query text.
  #
  # The key includes the current tenant because the session cookie is shared
  # across org subdomains (config.x.cookie_domain); Move ids are globally-unique
  # UUIDs so a cross-tenant collision can't actually occur, but scoping by tenant
  # keeps one org's terms structurally unreachable from another (defense-in-depth
  # matching the schema-per-tenant isolation posture).
  class RecentSearches
    SESSION_KEY = "recent_searches"
    MAX = 5            # queries kept per Move
    MAX_MOVES = 3      # Moves tracked at once (LRU-evicted)
    MAX_BYTES = 80     # bytes kept per query (byte-, not char-, bounded)

    def initialize(session, move)
      @session = session
      @move = move
    end

    # The Move's recent successful queries, most-recent-first.
    def list
      store[move_key] || []
    end

    # Record a successful query at the front of this Move's list. Case-insensitive
    # dedupe keeps the freshest casing; the query is clamped to MAX_LENGTH and the
    # list to MAX. Recording promotes this Move to most-recently-used and evicts
    # the oldest Move beyond MAX_MOVES. Blank queries are ignored. Returns the
    # updated list.
    def record(query)
      q = clamp(query)
      return list if q.blank?

      data = store
      kept = (data[move_key] || []).reject { |existing| existing.casecmp?(q) }
      data.delete(move_key) # re-insert last so this Move is the most-recently-used
      data[move_key] = [q, *kept].first(MAX)
      data.delete(data.keys.first) while data.size > MAX_MOVES
      @session[SESSION_KEY] = data
      data[move_key]
    end

    private

    # Strip, then clamp to a byte budget on a character boundary — `byteslice`
    # alone can split a multibyte char, so `scrub("")` drops the dangling bytes.
    def clamp(query)
      q = query.to_s.strip
      return q if q.bytesize <= MAX_BYTES

      q.byteslice(0, MAX_BYTES).scrub("")
    end

    def move_key
      "#{Apartment::Tenant.current}:#{@move.id}"
    end

    def store
      @session[SESSION_KEY] || {}
    end
  end
end
