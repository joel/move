# frozen_string_literal: true

module Moves
  # F2 — aggregates a Move's boxes into volume + weight totals, a per-room
  # breakdown, and honest missing-dimension counts. Volume and weight are derived
  # in code from canonical metric storage and never persisted (Technical
  # Foundation §6.2). Read-only: viewing the summary emits an auditable
  # "move.summary_viewed" event (the events-not-callbacks convention used across
  # the domain) but mutates nothing, so it works on an archived Move too.
  class VolumeSummary < BaseAction
    # One room's rollup. `room` is nil for the bucket of boxes with no room.
    # `volume_cm3` / `weight_kg` are nil when *no* box in the bucket contributed a
    # value (every box missing dimensions / no weight recorded), which lets the
    # view distinguish "nothing measured yet" from a genuine zero.
    RoomSummary = Data.define(:room, :box_count, :volume_cm3, :weight_kg, :missing_dimension_count)

    Result = Data.define(
      :total_volume_cm3, :total_weight_kg, :box_count, :missing_dimension_count, :rooms
    )

    def call(move:, actor: nil)
      boxes = move.boxes.includes(:room).to_a
      result = build(boxes)
      yield emit_event(move, actor)
      Success(result)
    end

    private

    def build(boxes)
      rooms = boxes
              .group_by(&:room)
              .map { |room, room_boxes| room_summary(room, room_boxes) }
              .sort_by { |rs| [rs.room ? 0 : 1, -(rs.volume_cm3 || 0)] }

      Result.new(
        total_volume_cm3: sum_volume(boxes),
        total_weight_kg: sum_weight(boxes),
        box_count: boxes.size,
        missing_dimension_count: boxes.count(&:missing_dimensions?),
        rooms: rooms
      )
    end

    def room_summary(room, boxes)
      RoomSummary.new(
        room: room,
        box_count: boxes.size,
        volume_cm3: sum_volume(boxes),
        weight_kg: sum_weight(boxes),
        missing_dimension_count: boxes.count(&:missing_dimensions?)
      )
    end

    # nil when nothing contributed, otherwise the summed canonical volume.
    def sum_volume(boxes)
      values = boxes.filter_map(&:volume_cm3)
      values.empty? ? nil : values.sum
    end

    def sum_weight(boxes)
      values = boxes.filter_map(&:weight_kg)
      values.empty? ? nil : values.sum
    end

    def emit_event(move, actor)
      Rails.event.notify("move.summary_viewed", move_id: move.id, actor_id: actor&.id)
      Success()
    end
  end
end
