# frozen_string_literal: true

module Items
  # Inverse of Items::Delete — undeletes a discarded Item (Domain §11). Distinct
  # from Items::RestoreToBox (the unpacking `presence_state` inverse, which emits
  # `item.restored`); this emits `item.undeleted` so the feed never conflates the
  # two. The caller resolves the Item with `with_discarded`.
  #
  # Refused with Failure(:parent_discarded) while the item's box is discarded
  # (#894): an item deleted on its own BEFORE its box was deleted keeps its own
  # batch, so the box cascade never touched it — restoring it alone would make
  # it kept inside a deleted box, which every "kept item ⇒ kept box" read
  # (the find-list counts, the box grid) assumes cannot happen. The user
  # restores the box first, then the item.
  class Restore < BaseAction
    include MoveWritable

    #: (item: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, actor:, source: :web)
      yield ensure_writable(item.move) # first step: no lock taken on a read-only Move
      batch_id = item.discard_batch_id
      yield restore_in_kept_box(item, actor, source)
      yield restore_source_photo(item)
      yield emit_event(item, actor, source, batch_id)
      Success(item)
    end

    private

    # The box check and the undiscard run under the box's row lock — the same
    # PARENT_ROW_LOCK Boxes::Delete's cascade takes on the box first — so a
    # concurrent box delete either commits before us (we see it discarded and
    # refuse) or waits and then cascades over the item we just restored. A
    # discarded item cannot be moved, so its box_id is stable: no
    # CurrentBoxLock re-read is needed. with_lock reloads unscoped, so the
    # check sees a box discarded while we waited.

    #: (untyped item, untyped actor, Symbol source) -> Dry::Monads::Result[untyped, untyped]
    def restore_in_kept_box(item, actor, source)
      # Expired outranks "restore the box first": the box was deleted after
      # this record, so its own window lapses first and restoring the box
      # could never make this one restorable again.
      return Failure(:retention_expired) if item.retention_expired?

      box = Box.with_discarded.find_by(id: item.box_id) or return Failure(:not_found)
      box.with_lock(PARENT_ROW_LOCK) do
        next Failure(:parent_discarded) if box.discarded?

        Discards::CascadeRestore.new.call(record: item, actor: actor, source: source)
      end
    end

    # A photo must be visible whenever a kept item references it. Items::Remove
    # discards a shared photo only once its LAST referencing item is removed —
    # under THAT item's batch, which may differ from this one's (two items can
    # share a photo and be deleted separately). So matching the photo by this
    # item's batch would miss it. Instead, simply un-discard the restored item's
    # own source photo if it's discarded — the item now references it again.
    # Media isn't a structural discard child of Item, so CascadeRestore won't.

    #: (untyped item) -> Dry::Monads::Result[untyped, untyped]
    def restore_source_photo(item)
      media = Media.with_discarded.find_by(id: item.source_media_id)
      return Success() unless media&.discarded?

      media.undiscard_in_batch!
      Success()
    rescue ActiveRecord::RecordInvalid, Discard::RecordNotUndiscarded => e
      Failure(e.message)
    end

    #: (untyped item, untyped actor, Symbol source, untyped batch_id) -> Dry::Monads::Success[nil]
    def emit_event(item, actor, source, batch_id)
      Rails.event.notify(
        "item.undeleted", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                          actor_id: actor&.id, source: source, discard_batch_id: batch_id
      )
      Success()
    end
  end
end
