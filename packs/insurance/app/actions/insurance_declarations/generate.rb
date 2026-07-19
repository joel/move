# frozen_string_literal: true

# pack_public: true -- public API of packs/insurance (the controller's entry point).
# Kept in the action layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module InsuranceDeclarations
  # #702 — assembles the movers-facing insurance declaration: every kept in_box
  # item exactly once, grouped by the recognition `family` facet (#626 — this is
  # that column's one and only rendering consumer; nil/blank families collect in
  # a final "Miscellaneous" bucket so the list stays exhaustive), names
  # aggregated with counts. Deliberately carries NO box numbers, NO room names
  # and NO photos — the declaration must not let the moving company locate
  # valuables (the whole point of the two-list design).
  #
  # Producing the document is auditable like the box manifest (Domain §12.3), so
  # the side effect goes through Rails.event ("insurance.declaration_generated")
  # → Insurance::AuditSubscriber. Read-only — NOT ensure_writable-guarded: an
  # archived Move may still be declared for insurance.
  class Generate < BaseAction
    # The declaration renders synchronously in-request, and prawn-table's
    # layout cost grows super-linearly with ROW count — an uncapped Move-wide
    # table could hold a Puma worker for tens of seconds. The rows are unique
    # (family, name) LINES, not items ("Moving boxes ×40" is one row), so the
    # cap binds to lines: a many-items Move with ordinary name reuse renders
    # fine (#705 — the original items-summed cap rejected a real 1,000+-item
    # Move whose table was small).
    MAX_LINES = 1_000

    # Trim + case-fold in SQL so " Kitchenware" and "kitchenware " merge; an
    # empty string folds into the nil (Miscellaneous) bucket via NULLIF — and so
    # does a literal "miscellaneous" family, which would otherwise render a
    # second, identically-headed section sorted among the m's.
    FAMILY_NORM = "NULLIF(NULLIF(BTRIM(LOWER(items.family)), ''), 'miscellaneous')"

    #: (move: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, actor:)
      # The cap is enforced on the SAME aggregate that renders — a separate
      # pre-count would race concurrent packing (TOCTOU) — and LIMIT bounds the
      # fetched rows, so memory stays bounded for an over-cap Move. Item count
      # deliberately does NOT gate: it drives no render cost (the aggregation
      # is SQL-side and the total is just a printed number).
      rows = grouped_rows(move)
      return Failure(:too_many_lines) if rows.size > MAX_LINES

      total_items = rows.values.sum
      sections = build_sections(rows)
      yield emit_event(move, actor, total_items)
      Success(sections: sections, total_items: total_items)
    end

    private

    # One aggregated query (AGENTS §1 #5): one row per (family, name) pair with
    # its count, ordered family-alphabetical with NULLS LAST — which lands the
    # Miscellaneous bucket at the end for free — then names alphabetical (a
    # declaration is a checking document; lookup order beats recency). LIMIT
    # bounds the fetched line rows for the cap check above.

    #: (untyped move) -> untyped
    def grouped_rows(move)
      move.items.in_box
          .group(Arel.sql(FAMILY_NORM), :name)
          .order(Arel.sql("#{FAMILY_NORM} ASC NULLS LAST"), name: :asc)
          .limit(MAX_LINES + 1)
          .count
    end

    # Shapes the already-aggregated rows into ordered sections:
    # [{ family: "kitchenware" | nil, lines: [[name, count], ...] }, ...] —
    # nil = the catch-all bucket; its printed label ("Miscellaneous") belongs to
    # the PDF renderer, like all PDF copy. Ruby here only partitions the
    # one-row-per-line aggregate — the totals are summed from the same data
    # that prints, so the cover count can never disagree with the listed lines.

    #: (untyped rows) -> Array[Hash[Symbol, untyped]]
    def build_sections(rows)
      rows.group_by { |(family, _name), _count| family }
          .map { |family, lines| { family:, lines: lines.map { |(_f, name), count| [name, count] } } }
    end

    #: (untyped move, untyped actor, Integer total_items) -> Dry::Monads::Success[nil]
    def emit_event(move, actor, total_items)
      Rails.event.notify(
        "insurance.declaration_generated",
        move_id: move.id, actor_id: actor&.id, item_count: total_items
      )
      Success()
    end
  end
end
