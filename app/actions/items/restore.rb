# frozen_string_literal: true

module Items
  # Inverse of Items::Delete — undeletes a discarded Item (Domain §11). Distinct
  # from Items::RestoreToBox (the unpacking `presence_state` inverse, which emits
  # `item.restored`); this emits `item.undeleted` so the feed never conflates the
  # two. The caller resolves the Item with `with_discarded`.
  class Restore < BaseAction
    def call(item:, actor:, source: :web)
      batch_id = item.discard_batch_id
      yield Discards::CascadeRestore.new.call(record: item, actor: actor, source: source)
      yield restore_orphaned_media(item, batch_id)
      yield emit_event(item, actor, source, batch_id)
      Success(item)
    end

    private

    # Items::Remove discards the item's now-orphaned source photo under the same
    # batch (parent = the item) — Media isn't a structural discard child of Item,
    # so the cascade-restore above won't touch it. Restore any photo tagged with
    # this batch + parent, mirroring the cascade's batch/parent-matched invariant
    # (a photo discarded for another reason carries a different batch and is left).
    def restore_orphaned_media(item, batch_id)
      return Success() unless batch_id

      Media.with_discarded.where(
        discard_batch_id: batch_id,
        discarded_by_parent_type: Item.base_class.name,
        discarded_by_parent_id: item.id
      ).find_each(&:undiscard_in_batch!)
      Success()
    rescue ActiveRecord::RecordInvalid, Discard::RecordNotUndiscarded => e
      Failure(e.message)
    end

    def emit_event(item, actor, source, batch_id)
      Rails.event.notify(
        "item.undeleted", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                          actor_id: actor&.id, source: source, discard_batch_id: batch_id
      )
      Success()
    end
  end
end
