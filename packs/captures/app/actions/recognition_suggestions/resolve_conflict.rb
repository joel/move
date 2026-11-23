# frozen_string_literal: true

# pack_public: true -- public API of packs/captures: ReviewsController calls it.
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module RecognitionSuggestions
  # Settles a `conflict` suggestion (#881). Recognition matched an item already
  # confirmed in the box, so it recorded the detection as a conflict and created
  # nothing (no-overwrite, Domain §6.4). A person makes the call:
  #  - outcome :same ("Same item") — the detection IS the matched item. The
  #    suggestion becomes `accepted`, still linked to it; nothing is created and
  #    the matched item is untouched. Emits recognition_suggestion.conflict_dismissed.
  #  - outcome :second ("Keep both") — the box holds a second one. Materialises
  #    the item recognition held back, sourced to the photo and this suggestion
  #    as RecognitionRuns::Process would have built it, but born `confirmed`
  #    because a person decided. The suggestion becomes `accepted`, linked to the
  #    new item. Emits item.created, then recognition_suggestion.conflict_kept_both.
  # Success value: the item the decision is about (matched, or new).
  #
  # Guards run under the box lock (PARENT_ROW_LOCK, the lock recognition's
  # materialize takes) on a re-read suggestion, so a double-submit, a stale tab
  # or a concurrent re-scan settles at most once:
  #  - :not_conflict — already settled (by this person or another);
  #  - :superseded — a newer run re-scanned the photo, so this conflict no
  #    longer describes it (#899, the latest-run rule);
  #  - :box_unpacked — the box is terminal (#855), nothing may change in it.
  # Events are emitted after the commit.
  class ResolveConflict < BaseAction
    OUTCOMES = %i[same second].freeze

    #: (suggestion: untyped, actor: untyped, outcome: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(suggestion:, actor:, outcome:)
      return Failure(:unknown_outcome) unless OUTCOMES.include?(outcome)

      yield ensure_writable(suggestion.move)
      matched_item_id = suggestion.item_id
      item = suggestion.box.with_lock(PARENT_ROW_LOCK) do
        suggestion.lock!
        yield ensure_resolvable(suggestion)
        yield with_responsible(actor) { outcome == :same ? accept_match(suggestion) : keep_both(suggestion) }
      end
      emit(suggestion, actor, outcome, matched_item_id, item)
      Success(item)
    end

    private

    #: (untyped suggestion) -> Dry::Monads::Result[untyped, untyped]
    def ensure_resolvable(suggestion)
      return Failure(:not_conflict) unless suggestion.conflict?
      return Failure(:superseded) unless RecognitionRun.latest_for?(suggestion.recognition_run)
      return Failure(:box_unpacked) if suggestion.box.unpacked?

      Success()
    end

    #: (untyped suggestion) -> Dry::Monads::Result[untyped, untyped]
    def accept_match(suggestion)
      suggestion.update!(state: "accepted")
      Success(suggestion.item)
    end

    #: (untyped suggestion) -> Dry::Monads::Result[untyped, untyped]
    def keep_both(suggestion)
      item = suggestion.box.items.create!(
        move: suggestion.move, source_media: suggestion.media,
        source_recognition_suggestion_id: suggestion.id,
        name: suggestion.proposed_name, confidence_score: suggestion.confidence_score,
        created_via: "recognition", review_state: "confirmed", presence_state: "in_box"
      )
      suggestion.update!(state: "accepted", item:)
      Success(item)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped suggestion, untyped actor, Symbol outcome, untyped matched_item_id, untyped item) -> void
    def emit(suggestion, actor, outcome, matched_item_id, item)
      payload = { suggestion_id: suggestion.id, media_id: suggestion.media_id, box_id: suggestion.box_id,
                  move_id: suggestion.move_id, actor_id: actor&.id, item_id: matched_item_id }
      return Rails.event.notify("recognition_suggestion.conflict_dismissed", **payload) if outcome == :same

      Rails.event.notify("item.created", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                                         created_via: "recognition", created_by_id: actor&.id)
      Rails.event.notify("recognition_suggestion.conflict_kept_both", **payload, new_item_id: item.id)
    end
  end
end
