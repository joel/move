# frozen_string_literal: true

module Boxes
  # One-tap "next box of the same size" from the box card (#658): creates a
  # fresh box in the same Move copying only the source's dimensions. Number
  # sequencing, the QR token, the writable-Move guard, and the box.created
  # event all come from delegating to Boxes::Create; room, description, weight
  # and fragile deliberately stay blank — a duplicate is a new empty box of the
  # same size, not a clone of the contents' metadata.
  class Duplicate < BaseAction
    #: (box: untyped, creator: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(box:, creator:)
      Boxes::Create.new.call(move: box.move, params: dimension_params(box), creator: creator)
    end

    private

    #: (untyped box) -> Hash[Symbol, untyped]
    def dimension_params(box)
      # Derive from the model's canonical dimension set (which excludes
      # weight_kg) so a new dimension field can't be silently dropped here.
      Box::DIMENSIONS.index_with { |dim| box[dim] }
    end
  end
end
