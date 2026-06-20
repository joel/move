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
      result = build(move.boxes)
      yield emit_event(move, actor)
      Success(result)
    end

    private

    def build(boxes)
      rooms = room_summaries(boxes)
      Result.new(
        # Totals fold the per-room subtotals (O(rooms)), not the boxes.
        total_volume_cm3: combine(rooms.map(&:volume_cm3)),
        total_weight_kg: combine(rooms.map(&:weight_kg)),
        box_count: rooms.sum(&:box_count),
        missing_dimension_count: rooms.sum(&:missing_dimension_count),
        rooms: rooms
      )
    end

    # One grouped aggregate query per room instead of loading every box and
    # grouping/summing in Ruby. Volume = SUM(l*w*h): the product is NULL on any
    # missing dimension (so SQL excludes it), and SUM over an all-missing bucket
    # is NULL → nil, matching "nothing measured". Arel.sql aggregates come back
    # untyped (strings), so coerce: to_i counts, &.to_d the numeric sums.
    def room_summaries(boxes)
      rows = boxes.group(:room_id).pluck(
        :room_id,
        Arel.sql("COUNT(*)"),
        Arel.sql("SUM(length_cm * width_cm * height_cm)"),
        Arel.sql("SUM(weight_kg)"),
        Arel.sql("COUNT(*) FILTER (WHERE length_cm IS NULL OR width_cm IS NULL OR height_cm IS NULL)")
      )
      rooms_by_id = Room.where(id: rows.filter_map(&:first)).index_by(&:id)
      summaries = rows.map { |row| to_room_summary(row, rooms_by_id) }
      # Assigned rooms first by volume desc, the unassigned bucket last.
      summaries.sort_by { |rs| [rs.room ? 0 : 1, -(rs.volume_cm3 || 0)] }
    end

    def to_room_summary(row, rooms_by_id)
      room_id, count, volume, weight, missing = row
      RoomSummary.new(
        room: rooms_by_id[room_id],
        box_count: count.to_i,
        volume_cm3: volume&.to_d,
        weight_kg: weight&.to_d,
        missing_dimension_count: missing.to_i
      )
    end

    # nil when nothing contributed, otherwise the summed value.
    def combine(values)
      present = values.compact
      present.empty? ? nil : present.sum
    end

    def emit_event(move, actor)
      Rails.event.notify("move.summary_viewed", move_id: move.id, actor_id: actor&.id)
      Success()
    end
  end
end
