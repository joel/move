# frozen_string_literal: true

module Moves
  # Canonical starter vocabularies seeded into every new Move (see Moves::Create)
  # and reused by db/seeds.rb. Idempotent: keyed on name via
  # find_or_create_by!/find_or_initialize_by (matching the case-insensitive
  # `move_id, lower(name)` unique indexes), so re-running over an existing Move
  # never duplicates — even when a value was renamed to different casing
  # (matching Boxes::RoomResolution's case-insensitive resolve).
  module DefaultVocabularies
    ROOMS = [
      "Kitchen", "Living Room", "Master Bedroom", "Bedroom", "Bathroom",
      "Garage", "Office", "Hallway", "Dining Room", "Basement", "Attic", "Garden"
    ].freeze

    # Populates the Move's managed vocabulary (rooms — the only one left) with the
    # curated defaults. Caller owns the transaction (Moves::Create wraps it with the
    # Move + admin membership; db/seeds.rb calls it standalone).
    # Singleton defs aren't supported by inline RBS yet; skipped here, declared
    # in sig/default_vocabularies.rbs instead.

    # @rbs skip
    def self.apply(move)
      ROOMS.each { |name| find_or_create(move.rooms, name) }
    end

    # Case-insensitive lookup against the lower(name) unique index, so a value
    # renamed to different casing is reused rather than colliding on insert.
    # @rbs skip
    def self.existing(relation, name)
      relation.where("LOWER(name) = ?", name.downcase).first
    end
    private_class_method :existing

    # @rbs skip
    def self.find_or_create(relation, name)
      existing(relation, name) || relation.create!(name: name)
    end
    private_class_method :find_or_create
  end
end
