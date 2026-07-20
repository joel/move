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
    # The declaration renders synchronously in-request; the cap binds to
    # unique (family, name) LINES — the rendered rows. Recognition writes
    # mostly-unique names, so lines ≈ items on a recognized Move (#708 — a
    # 1,000-line cap was the same wall as the original item cap). The manual
    # row layout measures ~2s and ~213 body pages at 10,000 lines (inside
    # the 400-page budget), so 10,000 bounds pathology, not households.
    MAX_LINES = 10_000
    # Page budget: sections carry ~70pt of overhead (heading + column header +
    # spacing) vs 16pt rows, so 10,000 one-line FAMILIES would blow the page
    # assumption the line cap rests on (#709 review — family is unvalidated
    # provider output, so pathological family cardinality is possible).
    # USABLE discounts the section-keep break waste; the estimate over-counts.
    MAX_PAGES = 400
    SECTION_PT = 70
    # Per-line height depends on how far the (≤150-char) name wraps: ~14pt a
    # line at a conservative 60 chars/line, + the row gap. Estimated per line
    # below, not flat — a flat ROW_PT would under-count long-name moves.
    LINE_PT = 14
    ROW_GAP_PT = 4
    CHARS_PER_LINE = 60
    USABLE_PAGE_PT = 692

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

      sections = build_sections(rows)
      return Failure(:too_many_pages) if over_page_budget?(sections, rows)

      total_items = rows.values.sum
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

    # Length-aware: each line costs a wrapped-lines estimate of its (already
    # NAME_MAX-bounded) name, so long-name moves can't slip under a flat
    # per-row constant. Ruby arithmetic over the ≤MAX_LINES bounded rows.

    #: (untyped sections, untyped rows) -> bool
    def over_page_budget?(sections, rows)
      row_pt = rows.keys.sum do |(_family, name)|
        ((name.to_s.length.clamp(1, 150) / CHARS_PER_LINE.to_f).ceil * LINE_PT) + ROW_GAP_PT
      end
      (((sections.size * SECTION_PT) + row_pt) / USABLE_PAGE_PT.to_f) > MAX_PAGES
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
