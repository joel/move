# frozen_string_literal: true

module Boxes
  # Creates a Box inside the active tenant schema for a given Move. Assigns the
  # next box number (override allowed) and a permanent QR token, optionally
  # attaching a room (resolved by name from the minimal D2 vocabulary). The
  # caller owns the tenant context and the writable-Move guard (controller).
  class Create < BaseAction
    include Boxes::RoomResolution

    def call(move:, params:, creator:)
      yield ensure_writable(move)
      box = yield with_responsible(creator) { persist(move, params) }
      yield emit_event(box, creator)
      Success(box)
    end

    private

    # Room resolution and box creation share one transaction, so an invalid box
    # rolls back any room the name created (no orphan rooms on a failed create).
    def persist(move, params)
      box = nil
      ActiveRecord::Base.transaction do
        room = find_or_create_room(move, params[:room_name])
        box = move.boxes.create!(
          number: params[:number].presence || next_number(move),
          qr_token: SecureRandom.urlsafe_base64(16),
          room: room,
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
    def next_number(move)
      ((move.boxes.with_discarded.pluck(:number).map(&:to_i).max || 0) + 1).to_s
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
