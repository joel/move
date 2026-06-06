# frozen_string_literal: true

module Boxes
  # Shared by Boxes::Create and Boxes::Update: resolve a typed room name against
  # the Move's minimal room vocabulary (case-insensitive find-or-create). Blank
  # name → Success(nil). Returns a Dry::Monads result (host action includes them).
  module RoomResolution
    private

    def resolve_room(move, name)
      name = name.to_s.strip
      return Success(nil) if name.blank?

      room = move.rooms.where("LOWER(name) = ?", name.downcase).first
      Success(room || move.rooms.create!(name: name))
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end
  end
end
