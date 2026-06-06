# frozen_string_literal: true

module Boxes
  # Shared by Boxes::Create and Boxes::Update: resolve a typed room name against
  # the Move's minimal room vocabulary (case-insensitive find-or-create).
  #
  # Returns the Room (nil when the name is blank) and RAISES
  # ActiveRecord::RecordInvalid on an invalid room. Call it inside the action's
  # persistence transaction so a later box validation failure rolls back any
  # room it created — otherwise a failed/cancelled edit would leave an orphan
  # room polluting the vocabulary/filter.
  module RoomResolution
    private

    def find_or_create_room(move, name)
      name = name.to_s.strip
      return nil if name.blank?

      move.rooms.where("LOWER(name) = ?", name.downcase).first || move.rooms.create!(name: name)
    end
  end
end
