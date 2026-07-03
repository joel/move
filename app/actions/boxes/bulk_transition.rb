# frozen_string_literal: true

module Boxes
  # Advances every box in a source lifecycle state through one forward step in a
  # single operation (Phase 44) — the bulk companion to the per-box
  # Boxes::TransitionStatus. Reached from the Menu's "Bulk box steps" page:
  # "Seal all packing boxes", "Send all sealed boxes in transit", etc.
  #
  # Design (see doc/ai/v0.2/prompts/Phase 44 …):
  #   - **Reuse, don't duplicate.** Each box is transitioned through the existing
  #     Boxes::TransitionStatus, so the seal-requires-room guard, the
  #     unpacked->items cascade, and the box.status_changed event are all
  #     preserved with zero duplication.
  #   - **Forward steps only**, a curated subset of Box::TRANSITIONS (backward
  #     edges like sealed->packing are corrective and stay per-box).
  #   - **Best-effort partial**, not all-or-nothing: a roomless box can't be
  #     sealed (TransitionStatus returns :room_required); the bulk transitions
  #     every box it can and reports the skipped ones with reasons. Each per-box
  #     transition is itself atomic; the bulk is not wrapped in one transaction.
  #   - **SQL-only counts/filtering** (AGENTS.md §1 #5): the source-state set is a
  #     `where(status:)` SQL filter; iterating those rows to transition each is not
  #     the anti-pattern (we act on each row).
  class BulkTransition < BaseAction
    # The forward edges of Box::TRANSITIONS, ordered as the lifecycle flows. A
    # requested `to` outside this list is rejected (Failure(:invalid_step)).
    STEPS = [
      { from: "packing",    to: "sealed" },
      { from: "sealed",     to: "in_transit" },
      { from: "in_transit", to: "unpacking" },
      { from: "unpacking",  to: "unpacked" }
    ].freeze
    TARGETS = STEPS.pluck(:to).freeze
    SOURCE_FOR = STEPS.to_h { |s| [s[:to], s[:from]] }.freeze

    # `transitioned` is the count moved; `skipped` is [{ number:, reason: }] for
    # the boxes that couldn't move (e.g. roomless on a seal), so the controller
    # can report exactly which box numbers need attention.
    Result = Struct.new(:to, :transitioned, :skipped, keyword_init: true)

    #: (move: untyped, to: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, to:, actor:)
      yield ensure_writable(move)
      to = to.to_s
      return Failure(:invalid_step) unless TARGETS.include?(to)

      results = transition_each(move, to, actor)
      Success(
        Result.new(
          to: to,
          transitioned: results.count { |(_, r)| r.success? },
          skipped: results.reject { |(_, r)| r.success? }
                          .map { |(box, r)| { number: box.number, reason: r.failure } }
        )
      )
    end

    private

    # SQL-scoped to the source state, ordered by numeric label (so a skipped-box
    # report reads in print order). Each row is transitioned through the existing
    # per-box action — every guard, cascade and event preserved.

    #: (untyped move, untyped to, untyped actor) -> untyped
    def transition_each(move, to, actor)
      move.boxes.where(status: SOURCE_FOR.fetch(to)).ordered.map do |box|
        [box, Boxes::TransitionStatus.new.call(box: box, to: to, actor: actor)]
      end
    end
  end
end
