# frozen_string_literal: true

module MoveMcp
  module Tools
    # Returns the Move's volume/weight summary via the shared Moves::VolumeSummary
    # action (canonical metric; nil where nothing has been measured yet).
    class GetVolumeSummary < Base
      tool_name "get_volume_summary"
      description "Get the move's total volume, weight, box count, and per-room breakdown (metric)."
      input_schema(properties: {})

      def self.call(server_context:)
        result = ::Moves::VolumeSummary.new.call(move: move(server_context), actor: actor(server_context))
        return failure_response(result.failure) if result.failure?

        summary = result.value!
        data_response(
          total_volume_cm3: summary.total_volume_cm3,
          total_weight_kg: summary.total_weight_kg,
          box_count: summary.box_count,
          missing_dimension_count: summary.missing_dimension_count,
          rooms: summary.rooms.map { |room| room_json(room) }
        )
      end

      def self.room_json(room)
        {
          room: room.room&.name, box_count: room.box_count,
          volume_cm3: room.volume_cm3, weight_kg: room.weight_kg,
          missing_dimension_count: room.missing_dimension_count
        }
      end
    end
  end
end
