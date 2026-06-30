# frozen_string_literal: true

# pack_public: true -- public API of packs/photos: ReviewsController calls Photos::Move.
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Photos
  # Moves a photo (Media) and the items it sourced to another Box within the same
  # Move (#317). "Photo" is the user-facing word for a Media; the action lives under
  # Photos rather than Media because `Media` is the model constant (can't reopen a
  # class as a module). Decisions (#317): only items still *co-located* with the
  # photo travel (source_media_id = this photo AND still in its box AND in_box) —
  # items moved away individually or marked removed stay put; allowed in any box
  # phase (only the writable-Move guard applies, like Items::Move); recognition rows
  # keep their historical box.
  #
  # The photo and its items move in one locked transaction so they can never split
  # across boxes; the domain events (`item.moved` per item, `media.moved` for the
  # photo) are emitted *after* commit so the search reindex — which runs in a
  # separate queue DB, outside this transaction — observes the committed boxes
  # rather than the stale source box (Codex #318). `item.moved` reuses the existing
  # Search::IndexSubscriber + activity feed; only `box_id` changes, so presence
  # stays `in_box`.
  class Move < BaseAction
    def call(media:, target_box:, mover:)
      yield ensure_writable(media.move)
      yield validate(media, target_box)
      moved_item_ids = yield relocate(media, target_box)
      # :noop = a concurrent move already placed the photo in target while we waited
      # on the lock. The end state the caller wanted holds, so it's an idempotent
      # success (the controller redirects to the target box) — but emit nothing, as
      # this request moved nothing (no duplicate activity rows / reindex).
      emit_moves(media, moved_item_ids, target_box, mover) unless moved_item_ids == :noop
      Success(media)
    end

    private

    def validate(media, target_box)
      return Failure(:box_missing) if target_box.nil?
      return Failure(:same_box) if target_box.id == media.box_id
      return Failure(:cross_move) if target_box.move_id != media.move_id

      Success()
    end

    # Relocate the photo and its co-located items in one locked transaction; returns
    # the moved item ids. Emits NO events in here on purpose: an `item.moved` inside
    # this transaction enqueues the search reindex job, which lives in a *separate*
    # queue DB and so isn't covered by this app-DB transaction — it could run before
    # the move commits and index the items under the stale source box (Codex #318).
    # The caller emits the events after commit instead. The box update is done
    # directly (not via Items::Move) because that action's guards — in_box, not
    # same/cross box — are already satisfied by `co_located_items` + `validate`; only
    # `box_id` changes, so presence stays `in_box`.
    def relocate(media, target_box)
      result = nil
      ActiveRecord::Base.transaction do
        # FOR UPDATE: serialize concurrent moves of the same photo. Read the source
        # box only AFTER the lock so the second mover sees the first's committed box
        # and can't strand the photo apart from its items.
        media.lock!
        # Re-check after the lock: a concurrent move of the same photo to the SAME
        # target may have committed while we waited, so the pre-lock `validate`
        # same_box check is stale. Return an idempotent no-op (NOT Failure(:same_box),
        # which would make the controller redirect to the old box's review URL and
        # 404 — the photo already lives in target now) (Codex #318).
        result = if media.box_id == target_box.id
                   Success(:noop)
                 else
                   move_rows(media, target_box)
                 end
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Inside the photo lock: relocate the co-located items then the photo, returning
    # Success(moved_item_ids). FOR UPDATE on the items too — a concurrent individual
    # Items::Move on one of them would otherwise be clobbered (we'd overwrite its new
    # box). Locking + the `box_id = source_box_id` predicate means an item moved out
    # before our SELECT is simply not matched (its deliberate move is kept), and one
    # racing us blocks until we commit (Codex #318).
    def move_rows(media, target_box)
      items = co_located_items(media, media.box_id).lock.to_a
      items.each { |item| item.update!(box: target_box) }
      media.update!(box: target_box)
      Success(items.map(&:id))
    end

    # Items detected in this photo that are still in its box and present — the
    # photo's "current contents". Items already moved elsewhere (box_id differs) or
    # removed (presence_state) are intentionally excluded (#317 decision 1).
    def co_located_items(media, source_box_id)
      media.move.items.in_box.where(source_media_id: media.id, box_id: source_box_id)
    end

    # Emitted AFTER the transaction commits so each side effect — activity rows and
    # the search reindex job (its own queue DB) — observes the committed boxes.
    # `item.moved` mirrors Items::Move's payload (reuses Search::IndexSubscriber and
    # the activity feed); `media.moved` records the photo move itself.
    def emit_moves(media, item_ids, target_box, mover)
      item_ids.each do |id|
        Rails.event.notify(
          "item.moved", item_id: id, move_id: media.move_id, to_box_id: target_box.id, mover_id: mover&.id
        )
      end
      Rails.event.notify(
        "media.moved", media_id: media.id, move_id: media.move_id, to_box_id: target_box.id, mover_id: mover&.id
      )
    end
  end
end
