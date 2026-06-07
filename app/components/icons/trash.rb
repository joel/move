# frozen_string_literal: true

module Components
  module Icons
    class Trash < Components::Icons::Base
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M4 7h16")
          s.path(d: "M10 11v6")
          s.path(d: "M14 11v6")
          s.path(d: "M5 7l1 13a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2l1-13")
          s.path(d: "M9 7V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v3")
        end
      end
    end
  end
end
