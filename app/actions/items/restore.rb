# frozen_string_literal: true

module Items
  # Inverse of Items::Delete — undeletes a discarded Item (Domain §11). Distinct
  # from Items::RestoreToBox (the unpacking `presence_state` inverse, which emits
  # `item.restored`); this emits `item.undeleted` so the feed never conflates the
  # two. The caller resolves the Item with `with_discarded`.
  class Restore < BaseAction
    #: (item: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(item:, actor:, source: :web)
      batch_id = item.discard_batch_id
      yield Discards::CascadeRestore.new.call(record: item, actor: actor, source: source)
      yield restore_source_photo(item)
      yield emit_event(item, actor, source, batch_id)
      Success(item)
    end

    private

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
