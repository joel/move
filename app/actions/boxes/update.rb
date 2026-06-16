# frozen_string_literal: true

module Boxes
  # Updates a Box's editable attributes (number, room, dimensions, weight). The
  # caller owns the tenant context and the writable-Move guard (controller).
  # A blank room name leaves the existing room untouched (use D7 room management
  # to remove a room); a present name is resolved/created from the vocabulary.
  class Update < BaseAction
    include Boxes::RoomResolution
    include Search::Reindexing

    ATTRS = %i[number length_cm width_cm height_cm weight_kg description].freeze

    def call(box:, params:, editor:)
      yield ensure_writable(box.move)
      yield with_responsible(editor) { persist(box, params) }
      # Box number / room feed the items' search_text (Domain §7.3); the item rows
      # didn't change, so refresh their projections explicitly.
      reindex_items(box.items.ids) if box.saved_change_to_number? || box.saved_change_to_room_id?
      yield emit_event(box, editor)
      Success(box)
    end

    private

    # Room resolution and the box update share one transaction, so an invalid
    # box rolls back any room the name created (no orphan rooms on a failed edit).
    def persist(box, params)
      ActiveRecord::Base.transaction do
        attrs = params.slice(*ATTRS)
        attrs[:room] = find_or_create_room(box.move, params[:room_name]) if params[:room_name].present?
        box.update!(attrs)
      end
      Success(box)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(box, editor)
      Rails.event.notify("box.updated", box_id: box.id, move_id: box.move_id, editor_id: editor&.id)
      Success()
    end
  end
end
