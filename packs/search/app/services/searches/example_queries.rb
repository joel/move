# frozen_string_literal: true

# pack_public: true -- public API of packs/search: data-derived example queries (the searches controller calls it).
# Kept in its layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Searches
  # #922 — Example queries built from the Move's own data, offered under the
  # no-results empty state when the user has no recent searches (ux rules 4 & 5).
  # The Move's busiest room names come first, then its most common item names;
  # both are counted over searchable items only, so every suggestion can match.
  # Ranked and capped in SQL. The query that just failed is left out.
  class ExampleQueries
    LIMIT = 3

    #: (untyped move, ?exclude: untyped) -> void
    def initialize(move, exclude: nil)
      @move = move
      @exclude = exclude.to_s.strip.downcase
    end

    #: () -> Array[String]
    def list
      picks = [] #: Array[String]
      (room_names + item_names).each do |name|
        picks << name unless picks.any? { |pick| pick.casecmp?(name) }
      end
      picks.first(LIMIT)
    end

    private

    #: () -> Array[String]
    def room_names
      Room.where(move_id: @move.id)
          .joins(boxes: :items).merge(Item.searchable)
          .where.not("LOWER(rooms.name) = ?", @exclude)
          .group("rooms.id", "rooms.name")
          .order(Arel.sql("COUNT(items.id) DESC"), "rooms.name")
          .limit(LIMIT)
          .pluck("rooms.name")
    end

    #: () -> Array[String]
    def item_names
      @move.items.searchable
           .where.not("LOWER(items.name) = ?", @exclude)
           .group(Arel.sql("LOWER(items.name)"))
           .order(Arel.sql("COUNT(*) DESC, MIN(items.name)"))
           .limit(LIMIT)
           .pluck(Arel.sql("MIN(items.name)"))
    end
  end
end
