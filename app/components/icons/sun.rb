# frozen_string_literal: true

module Components
  module Icons
    class Sun < Components::Icons::Base
      def view_template
        svg(class: @css, **@attrs, viewBox: "0 0 20 20", fill: "none", aria_hidden: "true") do |s|
          s.path(
            d: "M10 4V2M10 18v-2M4.7 4.7l1.4 1.4M13.9 13.9l1.4 1.4M2 10h2M16 10h2M4.7 15.3l1.4-1.4M13.9 6.1l1.4-1.4",
            stroke: "currentColor",
            stroke_width: "1.4",
            stroke_linecap: "round"
          )
          s.circle(
            cx: "10",
            cy: "10",
            r: "3.2",
            stroke: "currentColor",
            stroke_width: "1.4"
          )
        end
      end
    end
  end
end
