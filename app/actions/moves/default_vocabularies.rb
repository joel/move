# frozen_string_literal: true

module Moves
  # Canonical starter vocabularies seeded into every new Move (see Moves::Create)
  # and reused by db/seeds.rb. Idempotent: keyed on name via
  # find_or_create_by!/find_or_initialize_by (matching the case-insensitive
  # `move_id, lower(name)` unique indexes), so re-running over an existing Move
  # never duplicates.
  module DefaultVocabularies
    ROOMS = [
      "Kitchen", "Living Room", "Master Bedroom", "Bedroom", "Bathroom",
      "Garage", "Office", "Hallway", "Dining Room", "Basement", "Attic", "Garden"
    ].freeze

    CATEGORIES = %w[
      Kitchenware Books Electronics Clothing Tools
      Furniture Decor Toys Documents Appliances
    ].freeze

    # name => applies_to (item / box / both)
    TAGS = {
      "Heavy" => "both", "Fragile" => "box", "Liquid" => "item",
      "Important" => "both", "Valuable" => "both", "Seasonal" => "item"
    }.freeze

    # Populates the Move's three managed vocabularies with the curated defaults.
    # Caller owns the transaction (Moves::Create wraps it with the Move + admin
    # membership; db/seeds.rb calls it standalone).
    def self.apply(move)
      ROOMS.each { |name| move.rooms.find_or_create_by!(name: name) }
      CATEGORIES.each { |name| move.categories.find_or_create_by!(name: name) }
      TAGS.each do |name, applies_to|
        tag = move.tags.find_or_initialize_by(name: name)
        tag.applies_to = applies_to
        tag.save!
      end
    end
  end
end
