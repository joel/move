# frozen_string_literal: true

module Items
  # Packing-phase removal: the user added an item by mistake and wants it *gone*
  # (it belongs in another box), as opposed to Items::MarkRemoved, which records
  # that an item was physically taken out during unpacking (the `presence_state`
  # axis). Soft-deletes the item and — when no other kept item still references its
  # source photo — that photo too, both under one discard batch so a single
  # Items::Restore brings them back. Emits `item.deleted` (same event as
  # Items::Delete, so the activity feed already offers a restore). Caller owns
  # tenant context. C3 only exposes this while the box is still packing.
  class Remove < BaseAction
    def call(item:, actor:, source: :web)
      yield ensure_packing_phase(item.box)
      media = item.source_media
      batch_id = yield Discards::Cascade.new.call(record: item, actor: actor, source: source)
      yield discard_orphaned_media(item, media, batch_id)
      yield emit_event(item, actor, source, batch_id)
      Success(item)
    end

    private

    # Deletion is a *packing-phase* operation only (#290). Once a box is sealed it
    # is closed — unseal it (sealed → packing) to edit its contents — and once it
    # is unpacking/unpacked the reversible presence transition (MarkRemoved) is the
    # right tool. Mirrors the capture/add gating (Box#capturable? is packing-only),
    # and the phase-aware UI must not be the only guard (a stale form or a direct
    # request could otherwise soft-delete closed-box inventory).
    def ensure_packing_phase(box)
      return Failure(:wrong_phase) unless box.packing?

      Success()
    end

    # Discard the source photo only when no *other kept* item still references it
    # (one photo can source several items — deleting one must not strip the photo
    # from its siblings). `Media#sourced_item?` is no help here: it queries
    # `with_discarded`, so it still counts the item we just discarded and would
    # never report the photo orphaned. Query kept items excluding this one instead.
    # The photo joins the item's batch (parent = the item) so Items::Restore
    # un-discards it too; the blob is kept (soft delete).
    def discard_orphaned_media(item, media, batch_id)
      return Success() unless media
      return Success() if item.move.items.where(source_media_id: media.id).where.not(id: item.id).exists?

      media.discard_in_batch!(batch_id: batch_id, parent: item)
      Success()
    rescue ActiveRecord::StatementInvalid, Discard::RecordNotDiscarded => e
      # Best-effort (#291/#293): the item discard is the primary effect and is
      # already committed by Discards::Cascade. A *DB-level* failure to also hide
      # the orphaned photo (the only two ways `discard_in_batch!` can fail: a bad
      # UPDATE → StatementInvalid, or the discard callback aborting →
      # RecordNotDiscarded) must not skip the `item.deleted` event and its
      # activity-feed restore affordance — a leftover-visible photo is the benign
      # outcome. Deliberately narrow: any other error (a real bug) propagates and
      # fails loudly rather than being swallowed.
      Rails.logger.error("Items::Remove: orphaned media discard failed (media=#{media.id}): #{e.message}")
      Success()
    end

    def emit_event(item, actor, source, batch_id)
      Rails.event.notify(
        "item.deleted", item_id: item.id, box_id: item.box_id, move_id: item.move_id,
                        actor_id: actor&.id, source: source, discard_batch_id: batch_id
      )
      Success()
    end
  end
end
