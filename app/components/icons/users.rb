# frozen_string_literal: true

module Components
  module Icons
    # A pair of people — the medallion for the Members & Roles destination.
    class Users < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M16 19v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2")
          s.circle(cx: "9", cy: "7", r: "4")
          s.path(d: "M22 19v-2a4 4 0 0 0-3-3.87")
          s.path(d: "M16 3.13a4 4 0 0 1 0 7.75")
        end
      end
    end
  end
end
