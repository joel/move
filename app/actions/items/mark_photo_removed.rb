# frozen_string_literal: true

module Items
  # Marks ALL of a photo's still-in-box items as removed in one step — the box
  # detail "Unpack photo" tap (#727). Most photos hold a single item, so the
  # photo is the natural unpacking unit; multi-item photos unpack their whole
  # set at once.
  #
  # Loops Items::MarkRemoved (which re-checks the unpacking phase and emits
  # item.removed per item) so the activity feed reads exactly as N checklist
  # taps would — no new event type, no new subscriber. Box-scoped on purpose:
  # an item moved to another box keeps its source_media_id, and unpacking THIS
  # box must not reach into that other box (mirrors the unpacked-badge
  # semantics in BoxesController#unpacked_media_ids).
  #
  # The photo must belong to THIS box (#729): the controller already scopes
  # the id to box.media, but the action states the invariant itself so any
  # future caller (an MCP bulk tool) gets Failure(:not_found) for a foreign
  # photo. Without it, an item moved INTO this box that still points at a
  # foreign photo would be unpacked.
  #
  # Serialized with Photos::Move / Items::Move, which relocate under the
  # source box's lock (Items::CurrentBoxLock): the ownership check + item load
  # run under this box's lock (PARENT_ROW_LOCK), and so does EACH removal,
  # which re-checks under the lock that the item is still in_box here before
  # writing (Codex #876 R1). A move committing between the load and an item's
  # turn re-boxes that item, so it is skipped — never unpacked in its new box.
  # Box-first, like Items::RestoreToBox; we hold no other row lock while
  # waiting, so no cycle with the movers (box → photo → items).
  #
  # Returns Success(items:, completed_box:, photo_moved:) — photo_moved is
  # true when the photo left this box mid-loop (see moved_away?).
  #
  # No wrapping transaction: each item runs in its own short box-locked
  # transaction and commits before the next, so every success is durable,
  # per the bulk best-effort convention. MarkRemoved emits only after its
  # write succeeds, so no event can outlive a rollback; the in-lock event's
  # side effects are commit-safe (activity row in the same transaction,
  # search enqueue deferred to commit #648, cluster refresh a debounced job).
  class MarkPhotoRemoved < BaseAction
    #: (box: untyped, media: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(box:, media:, actor:)
      yield ensure_writable(box.move)
      # Guarded here too (not only via the per-item loop) so a photo whose
      # items are all already removed still fails correctly on a wrong phase.
      yield ensure_unpacking_phase(box)

      candidates = yield owned_items(box, media)
      items = candidates.filter_map { |item| yield remove_if_still_here(box, item, actor) }
      # The bulk counterpart of Items::Unpack (#755): unpacking the box's last
      # photo completes the box — owned here, not by the adapter, so the rule
      # cannot drift. Post-loop, own box lock (#739 R2); completed_box never
      # fails the already-committed removals (#756 R4).
      Success(items: items, completed_box: Boxes::CompleteIfEmpty.completed_box(box: box, actor: actor),
              photo_moved: moved_away?(box, media))
    end

    private

    # :move preloaded — the per-item MarkRemoved guard reads it, and the loop
    # must not re-load it per item (Bullet); each item's box is pointed at the
    # locked box in remove_if_still_here.

    #: (untyped box, untyped media) -> Dry::Monads::Result[untyped, untyped]
    def owned_items(box, media)
      box.with_lock(PARENT_ROW_LOCK) do
        next Failure(:not_found) unless owned?(box, media)

        Success(box.items.in_box.where(source_media_id: media.id).includes(:move).order(:created_at, :id).to_a)
      end
    end

    # The CurrentBoxLock re-read (#840/#864): the caller's Media may predate a
    # concurrent Photos::Move, so it is re-read UNDER the box lock — any move
    # off this box has committed by now (it holds this lock while it writes)
    # or will wait behind us. Media#reload is unscoped, so a photo discarded
    # meanwhile still reloads; a hard-deleted one raises.

    #: (untyped box, untyped media) -> bool
    def owned?(box, media)
      media.reload.box_id == box.id && !media.discarded?
    rescue ActiveRecord::RecordNotFound
      false
    end

    # A Photos::Move can commit between two per-item transactions and take the
    # photo (with its remaining items) to another box (#877): the loop then
    # skips them, so success alone can't tell "unpacked" from "moved away".
    # Re-read under the box lock, like the opening check; the caller drops the
    # photo's card from this box instead of redrawing a photo it no longer holds.

    #: (untyped box, untyped media) -> bool
    def moved_away?(box, media)
      box.with_lock(PARENT_ROW_LOCK) { !owned?(box, media) }
    end

    # Success(item) when removed, Success(nil) when the item left this box
    # (or was already removed) since the load. The item points at the locked,
    # freshly re-read box, so MarkRemoved's phase guard sees the current status.

    #: (untyped box, untyped item, untyped actor) -> Dry::Monads::Result[untyped, untyped]
    def remove_if_still_here(box, item, actor)
      box.with_lock(PARENT_ROW_LOCK) do
        next Success(nil) unless box.items.in_box.exists?(item.id)

        item.box = box
        MarkRemoved.new.call(item: item, actor: actor)
      end
    end

    #: (untyped box) -> Dry::Monads::Result[untyped, untyped]
    def ensure_unpacking_phase(box)
      return Failure(:wrong_phase) unless box.unpacking? || box.unpacked?

      Success()
    end
  end
end
