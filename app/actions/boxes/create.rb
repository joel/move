# frozen_string_literal: true

module Boxes
  # Creates a Box inside the active tenant schema for a given Move. Assigns the
  # next box number (override allowed) and a permanent QR token, optionally
  # attaching a room (resolved by name from the minimal D2 vocabulary). The
  # caller owns the tenant context and the writable-Move guard (controller).
  class Create < BaseAction
    include Boxes::RoomResolution

    #: (move: untyped, params: untyped, creator: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, params:, creator:)
      yield ensure_writable(move)
      box = yield with_responsible(creator) { persist(move, params) }
      yield emit_event(box, creator)
      Success(box)
    end

    private

    # Room resolution and box creation share one transaction, so an invalid box
    # rolls back any room the name created (no orphan rooms on a failed create).

    #: (untyped move, untyped params) -> Dry::Monads::Result[untyped, untyped]
    def persist(move, params)
      box = nil
      ActiveRecord::Base.transaction do
        room = find_or_create_room(move, params[:room_name])
        box = move.boxes.create!(
          number: params[:number].presence || next_number(move),
          qr_token: SecureRandom.urlsafe_base64(16),
          room: room,
          description: params[:description],
          **dimensions(params)
        )
      end
      Success(box)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Span discarded boxes too: a box's number stays reserved while soft-deleted
    # (the uniqueness validator ignores default_scope, so it checks every row), and
    # restoring it must be lossless. Numbering off the kept-only max would re-pick a
    # discarded box's number, and the plain "Add box" would then fail validation
    # with "Number has already been taken" (#192).

    #: (untyped move) -> String
    def next_number(move)
      # Highest existing number + 1, computed in SQL (MAX), not by loading every
      # number into Ruby. number is a string column, so the Arel.sql cast comes
      # back untyped (a string) — to_i coerces it (nil → 0 for the first box).
      (move.boxes.with_discarded.maximum(Arel.sql("number::bigint")).to_i + 1).to_s
    end

    #: (untyped params) -> untyped
    def dimensions(params)
      params.slice(:length_cm, :width_cm, :height_cm, :weight_kg)
    end

    #: (untyped box, untyped creator) -> Dry::Monads::Success[nil]
    def emit_event(box, creator)
      Rails.event.notify("box.created", box_id: box.id, move_id: box.move_id, created_by_id: creator&.id)
      Success()
    end
  end
end
