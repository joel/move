# frozen_string_literal: true

module Boxes
  # Updates a Box's editable attributes (number, room, dimensions, weight). The
  # caller owns the tenant context and the writable-Move guard (controller).
  # A blank room name leaves the existing room untouched (use D7 room management
  # to remove a room); a present name is resolved/created from the vocabulary.
  class Update < BaseAction
    include Boxes::RoomResolution

    ATTRS = %i[number length_cm width_cm height_cm weight_kg].freeze

    def call(box:, params:, editor:)
      room = yield resolve_room(box.move, params[:room_name])
      yield persist(box, params, room)
      yield emit_event(box, editor)
      Success(box)
    end

    private

    def persist(box, params, room)
      attrs = params.slice(*ATTRS)
      attrs[:room] = room if params[:room_name].present?
      box.update!(attrs)
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
