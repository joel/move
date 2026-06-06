# frozen_string_literal: true

module Boxes
  # Creates a Box inside the active tenant schema for a given Move. Assigns the
  # next box number (override allowed) and a permanent QR token, optionally
  # attaching a room (resolved by name from the minimal D2 vocabulary). The
  # caller owns the tenant context and the writable-Move guard (controller).
  class Create < BaseAction
    def call(move:, params:, creator:)
      room = yield resolve_room(move, params[:room_name])
      box = yield persist(move, params, room)
      yield emit_event(box, creator)
      Success(box)
    end

    private

    # Case-insensitive find-or-create so "kitchen" reuses an existing "Kitchen".
    def resolve_room(move, name)
      name = name.to_s.strip
      return Success(nil) if name.blank?

      room = move.rooms.where("LOWER(name) = ?", name.downcase).first
      Success(room || move.rooms.create!(name: name))
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def persist(move, params, room)
      box = move.boxes.create!(
        number: params[:number].presence || next_number(move),
        qr_token: SecureRandom.urlsafe_base64(16),
        room: room,
        **dimensions(params)
      )
      Success(box)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def next_number(move)
      ((move.boxes.pluck(:number).map(&:to_i).max || 0) + 1).to_s
    end

    def dimensions(params)
      params.slice(:length_cm, :width_cm, :height_cm, :weight_kg)
    end

    def emit_event(box, creator)
      Rails.event.notify("box.created", box_id: box.id, move_id: box.move_id, created_by_id: creator&.id)
      Success()
    end
  end
end
