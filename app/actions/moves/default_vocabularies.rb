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
      ROOMS.each { |name| find_or_create(move.rooms, name) }
      CATEGORIES.each { |name| find_or_create(move.categories, name) }
      # Additive only, like rooms/categories: create a missing tag with its default
      # facet, but never overwrite an existing tag's `applies_to`. On a backfill over
      # an existing Move that would silently narrow e.g. a user's item-scoped
      # `Fragile` to box-only, skipping the detach/reindex that Vocabularies::Update
      # performs and orphaning item<->tag links (#168). Defaults fill gaps; the user's
      # facet choices win.
      TAGS.each do |name, applies_to|
        next if existing(move.tags, name)

        move.tags.create!(name: name, applies_to: applies_to)
      end
    end

    # Case-insensitive lookup against the lower(name) unique index, so a value
    # renamed to different casing is reused rather than colliding on insert.
    def self.existing(relation, name)
      relation.where("LOWER(name) = ?", name.downcase).first
    end
    private_class_method :existing

    def self.find_or_create(relation, name)
      existing(relation, name) || relation.create!(name: name)
    end
    private_class_method :find_or_create
  end
end
