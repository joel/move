# frozen_string_literal: true

module Components
  module Icons
    # Two horizontal arrows pointing opposite ways — the "switch move" action.
    class Swap < Components::Icons::Base
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M7 4 3 8l4 4")
          s.path(d: "M3 8h14")
          s.path(d: "M17 20l4-4-4-4")
          s.path(d: "M21 16H7")
        end
      end
    end
  end
end
