# frozen_string_literal: true

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
  # Each item moves through Items::Move so it inherits that action's guards, the
  # `item.moved` event (activity feed + search reindex), and the in_box presence
  # rule — then the photo's own box_id follows, all in one transaction so the photo
  # and its items can never split across boxes. Emits `media.moved` for the photo.
  class Move < BaseAction
    def call(media:, target_box:, mover:)
      yield ensure_writable(media.move)
      yield validate(media, target_box)
      yield relocate(media, target_box, mover)
      yield emit_event(media, target_box, mover)
      Success(media)
    end

    private

    def validate(media, target_box)
      return Failure(:box_missing) if target_box.nil?
      return Failure(:same_box) if target_box.id == media.box_id
      return Failure(:cross_move) if target_box.move_id != media.move_id

      Success()
    end

    # Move the co-located items, then the photo, atomically. A single item failing
    # (it shouldn't — the set is pre-filtered to movable items) rolls the whole
    # relocation back and surfaces that failure rather than half-moving the photo.
    def relocate(media, target_box, mover)
      source_box_id = media.box_id
      failure = nil
      ActiveRecord::Base.transaction do
        co_located_items(media, source_box_id).each do |item|
          result = Items::Move.new.call(item: item, target_box: target_box, mover: mover)
          next if result.success?

          failure = result
          raise ActiveRecord::Rollback
        end
        media.update!(box: target_box)
      end
      failure || Success()
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Items detected in this photo that are still in its box and present — the
    # photo's "current contents". Items already moved elsewhere (box_id differs) or
    # removed (presence_state) are intentionally excluded (#317 decision 1).
    def co_located_items(media, source_box_id)
      media.move.items.in_box.where(source_media_id: media.id, box_id: source_box_id)
    end

    def emit_event(media, target_box, mover)
      Rails.event.notify(
        "media.moved", media_id: media.id, move_id: media.move_id,
                       to_box_id: target_box.id, mover_id: mover&.id
      )
      Success()
    end
  end
end
