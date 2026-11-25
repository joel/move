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
  # source phase (only the writable-Move guard applies, like Items::Move), but an
  # `unpacked` destination is refused (Failure(:box_unpacked), #947): its items
  # would land in_box inside a completed box. Recognition rows keep their
  # historical box.
  #
  # The photo and its items move in one locked transaction so they can never split
  # across boxes; the domain events (`item.moved` per item, `media.moved` for the
  # photo) are emitted *after* commit so the search reindex — which runs in a
  # separate queue DB, outside this transaction — observes the committed boxes
  # rather than the stale source box (Codex #318). `item.moved` reuses the existing
  # Search::IndexSubscriber + activity feed; only `box_id` changes, so presence
  # stays `in_box`.
  #
  # Moving the photo whose items are the last in-box items of an `unpacking` box
  # completes that SOURCE box (#838) — the same lifecycle rule as Items::Move
  # (#757, architecture.md §4c). The destination is never completed. Returns
  # Success(media:, source_box:, source_completed:): source_box is the box the
  # photo actually left (nil on the idempotent no-op), and source_completed is
  # that box's REALITY (it was unpacking and is now unpacked), not whether this
  # call won the completion race (#756 R7). The completion is a secondary
  # mutation, so its failure never fails the move.
  class Move < BaseAction
    include MoveWritable
    include Items::CurrentBoxLock

    #: (media: untyped, target_box: untyped, mover: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(media:, target_box:, mover:)
      yield ensure_writable(media.move)
      yield validate(media, target_box)
      relocated = yield relocate(media, target_box)
      # :noop = a concurrent move already placed the photo in target while we waited
      # on the lock. The end state the caller wanted holds, so it's an idempotent
      # success (the controller redirects to the target box) — but emit nothing and
      # complete nothing, as this request moved nothing (no duplicate activity rows
      # / reindex).
      return Success(media: media, source_box: nil, source_completed: false) if relocated == :noop

      source, moved_item_ids, eligible = relocated
      emit_moves(media, moved_item_ids, target_box, mover)
      Success(media: media, source_box: source, source_completed: source_completed?(source, eligible, mover))
    end

    private

    # Only a box the photo's items left while it was being unpacked (read under
    # the source lock) is eligible: a box opened AFTER we released the lock was
    # deliberately opened empty and must stay open (#757 Codex R9). Runs after
    # the move commits, in CompleteIfEmpty's own box lock (#756 R2 ordering).
    # Returns the source box's reality, re-read unscoped so a box a concurrent
    # delete discarded doesn't report as completed (#757 Codex R11).

    #: (untyped source, bool eligible, untyped mover) -> bool
    def source_completed?(source, eligible, mover)
      return false unless eligible

      Boxes::CompleteIfEmpty.completed_box(box: source, actor: mover)
      source.reload
      source.unpacked? && !source.discarded?
    end

    #: (untyped media, untyped target_box) -> Dry::Monads::Result[untyped, untyped]
    def validate(media, target_box)
      return Failure(:box_missing) if target_box.nil?
      return Failure(:same_box) if target_box.id == media.box_id
      return Failure(:cross_move) if target_box.move_id != media.move_id

      Success()
    end

    # Relocate the photo and its co-located items in one transaction, under the
    # lock of the box the photo is in NOW (Items::CurrentBoxLock, #838): box-first,
    # like Items::Move, so it serializes with a concurrent "mark box unpacked"
    # cascade, an Items::Move out of the same box, and another move of the same
    # photo (whose commit re-boxes it — the lock helper then re-locks the photo's
    # new box). The destination is locked too (`also_lock:`, #947), so its
    # `unpacked` guard holds until commit; the helper takes both FOR NO KEY
    # UPDATE locks in box id order, so two crossing moves can't deadlock. Emits NO events in here on purpose: an `item.moved` inside this
    # transaction enqueues the search reindex job, which lives in a *separate*
    # queue DB and so isn't covered by this app-DB transaction — it could run
    # before the move commits and index the items under the stale source box
    # (Codex #318). The caller emits the events after commit instead. The box
    # update is done directly (not via Items::Move) because that action's guards —
    # in_box, not same/cross box — are already satisfied by `co_located_items` +
    # `validate`; only `box_id` changes, so presence stays `in_box`.

    #: (untyped media, untyped target_box) -> Dry::Monads::Result[untyped, untyped]
    def relocate(media, target_box)
      with_current_box_lock(media, also_lock: target_box) { |box| locked_relocate(media, box, target_box) }
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Under the source box lock. Re-check after the lock: a concurrent move of the
    # same photo to the SAME target may have committed while we waited, so the
    # pre-lock `validate` same_box check is stale. Return an idempotent no-op (NOT
    # Failure(:same_box), which would make the controller redirect to the old
    # box's review URL and 404 — the photo already lives in target now) (Codex
    # #318). The photo row is locked too (box, then photo, then items — nothing
    # locks them the other way round): Photos::Delete locks the photo but not its
    # box, so the discarded check must follow that lock, or a delete committing
    # while we wait on the items would let us move a discarded photo. Returns
    # [source box, moved item ids, completion-eligible]: eligible only when items
    # actually left an `unpacking` box — a photo with no co-located items empties
    # nothing, and an empty box someone opened or reopened must stay open.

    #: (untyped media, untyped box, untyped target_box) -> Dry::Monads::Result[untyped, untyped]
    def locked_relocate(media, box, target_box)
      media.lock!(PARENT_ROW_LOCK) # reloads (unscoped): sees a concurrent discard
      return Failure(:not_found) if media.discarded?
      return Success(:noop) if box.id == target_box.id
      # Read as the destination's lock reloaded it (#947, like Items::Move #839).
      return Failure(:box_missing) if target_box.discarded?
      return Failure(:box_unpacked) if target_box.unpacked?

      moved_ids = move_rows(media, target_box)
      Success([box, moved_ids, moved_ids.any? && box.unpacking?])
    end

    # Inside the source box lock: relocate the co-located items then the photo,
    # returning the moved item ids. FOR UPDATE on the items — a concurrent individual
    # Items::Move on one of them would otherwise be clobbered (we'd overwrite its new
    # box). Locking + the `box_id = source_box_id` predicate means an item moved out
    # before our SELECT is simply not matched (its deliberate move is kept), and one
    # racing us blocks until we commit (Codex #318).

    #: (untyped media, untyped target_box) -> Array[untyped]
    def move_rows(media, target_box)
      items = co_located_items(media, media.box_id).lock.to_a
      items.each { |item| item.update!(box: target_box) }
      media.update!(box: target_box)
      items.map(&:id)
    end

    # Items detected in this photo that are still in its box and present — the
    # photo's "current contents". Items already moved elsewhere (box_id differs) or
    # removed (presence_state) are intentionally excluded (#317 decision 1).

    #: (untyped media, untyped source_box_id) -> untyped
    def co_located_items(media, source_box_id)
      media.move.items.in_box.where(source_media_id: media.id, box_id: source_box_id)
    end

    # Emitted AFTER the transaction commits so each side effect — activity rows and
    # the search reindex job (its own queue DB) — observes the committed boxes.
    # `item.moved` mirrors Items::Move's payload (reuses Search::IndexSubscriber and
    # the activity feed); `media.moved` records the photo move itself.

    #: (untyped media, untyped item_ids, untyped target_box, untyped mover) -> void
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
